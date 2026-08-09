import Foundation

enum HistoryMutationResult: Equatable {
    case inserted(UUID)
    case movedExisting(UUID)
    case rejectedOversize(UUID)
}

final class SnapshotLease {
    private let lock = NSLock()
    private var releaseHandler: (() -> Void)?

    init(releaseHandler: @escaping () -> Void) {
        self.releaseHandler = releaseHandler
    }

    func release() {
        lock.lock()
        let handler = releaseHandler
        releaseHandler = nil
        lock.unlock()
        handler?()
    }

    deinit {
        release()
    }
}

final class HistoryStore {
    private let lock = NSLock()
    private let manifestStore: ManifestStore<HistoryIndex>
    private let blobStore: BlobStore
    private let fileStore: FileSnapshotStore
    private let snapshotRepository: SnapshotRepository
    private var configuration: Configuration
    private var index: HistoryIndex
    private var protectedSnapshotIDs: Set<UUID> = []

    init(
        paths: StoragePaths,
        configuration: Configuration,
        blobStore: BlobStore? = nil,
        fileStore: FileSnapshotStore? = nil
    ) throws {
        try paths.createDirectories()
        let resolvedBlobStore = try blobStore ?? BlobStore(rootURL: paths.blobs)
        self.blobStore = resolvedBlobStore
        self.fileStore = try fileStore ?? FileSnapshotStore(rootURL: paths.files)
        self.snapshotRepository = SnapshotRepository(blobStore: resolvedBlobStore)
        self.manifestStore = ManifestStore(url: paths.history, corruptedDirectory: paths.corrupted)
        self.configuration = configuration
        self.index = try manifestStore.load(default: .empty)
        _ = try resolvedBlobStore.garbageCollect(
            referencedHashes: Self.referencedBlobHashes(in: index.snapshots)
        )
        try self.fileStore.garbageCollectUnreferencedSnapshots(
            referencedIDs: Set(index.snapshots.map(\.id))
        )
    }

    var count: Int {
        lock.withLock { index.snapshots.count }
    }

    var storageBytes: UInt64 {
        lock.withLock { storageBytesUnlocked(for: index.snapshots) }
    }

    func snapshotIDs() -> [UUID] {
        lock.withLock { index.snapshots.map(\.id) }
    }

    func snapshot(id: UUID) -> PasteboardSnapshot? {
        lock.withLock { index.snapshots.first { $0.id == id } }
    }

    @discardableResult
    func markRecentlyUsed(_ snapshotID: UUID) throws -> Bool {
        try lock.withLock {
            guard let position = index.snapshots.firstIndex(where: { $0.id == snapshotID }) else {
                return false
            }
            guard position != 0 else { return true }
            var updated = index.snapshots
            updated.insert(updated.remove(at: position), at: 0)
            let committed = HistoryIndex(version: 1, snapshots: updated)
            try manifestStore.save(committed)
            index = committed
            return true
        }
    }

    @discardableResult
    func add(_ snapshot: PasteboardSnapshot) throws -> HistoryMutationResult {
        try lock.withLock {
            guard snapshot.totalStoredBytes <= configuration.maximumSingleSnapshotBytes else {
                try? fileStore.removeSnapshot(snapshot.id)
                try removeUnreferencedBlobsUnlocked(from: [snapshot])
                return .rejectedOversize(snapshot.id)
            }
            try snapshotRepository.validate(snapshot)

            var candidates = index.snapshots
            let result: HistoryMutationResult
            var cleanupIDs: Set<UUID> = []
            var cleanupSnapshots: [PasteboardSnapshot] = []
            if let existingIndex = candidates.firstIndex(where: { $0.contentHash == snapshot.contentHash }) {
                let existing = candidates.remove(at: existingIndex)
                candidates.insert(existing, at: 0)
                cleanupIDs.insert(snapshot.id)
                cleanupSnapshots.append(snapshot)
                result = .movedExisting(existing.id)
            } else {
                candidates.insert(snapshot, at: 0)
                result = .inserted(snapshot.id)
            }

            let retained = retainedSnapshotsUnlocked(from: candidates)
            let evictedIDs = Set(candidates.map(\.id)).subtracting(retained.map(\.id))
            cleanupIDs.formUnion(evictedIDs)
            cleanupSnapshots.append(contentsOf: candidates.filter { evictedIDs.contains($0.id) })
            let committed = HistoryIndex(version: 1, snapshots: retained)
            try manifestStore.save(committed)
            index = committed

            for snapshotID in cleanupIDs where !protectedSnapshotIDs.contains(snapshotID) {
                try? fileStore.removeSnapshot(snapshotID)
            }
            try removeUnreferencedBlobsUnlocked(from: cleanupSnapshots)
            return result
        }
    }

    func acquireLease(for snapshotID: UUID) -> SnapshotLease? {
        lock.withLock {
            guard index.snapshots.contains(where: { $0.id == snapshotID }) else {
                return nil
            }
            protectedSnapshotIDs.insert(snapshotID)
            return SnapshotLease { [weak self] in
                _ = self?.lock.withLock {
                    self?.protectedSnapshotIDs.remove(snapshotID)
                }
            }
        }
    }

    func clear() throws {
        try lock.withLock {
            let retained = index.snapshots.filter { protectedSnapshotIDs.contains($0.id) }
            let removedSnapshots = index.snapshots.filter { !protectedSnapshotIDs.contains($0.id) }
            let removed = Set(removedSnapshots.map(\.id))
            let committed = HistoryIndex(version: 1, snapshots: retained)
            try manifestStore.save(committed)
            index = committed
            for snapshotID in removed {
                try? fileStore.removeSnapshot(snapshotID)
            }
            try removeUnreferencedBlobsUnlocked(from: removedSnapshots)
        }
    }

    func garbageCollectUnreferencedBlobs() throws {
        try lock.withLock {
            _ = try blobStore.garbageCollect(
                referencedHashes: Self.referencedBlobHashes(in: index.snapshots)
            )
        }
    }

    func updateConfiguration(_ configuration: Configuration) throws {
        try configuration.validate()
        try lock.withLock {
            self.configuration = configuration
            let retained = retainedSnapshotsUnlocked(from: index.snapshots)
            let retainedIDs = Set(retained.map(\.id))
            let removedSnapshots = index.snapshots.filter { !retainedIDs.contains($0.id) }
            let removed = Set(removedSnapshots.map(\.id))
            let committed = HistoryIndex(version: 1, snapshots: retained)
            try manifestStore.save(committed)
            index = committed
            for snapshotID in removed {
                try? fileStore.removeSnapshot(snapshotID)
            }
            try removeUnreferencedBlobsUnlocked(from: removedSnapshots)
        }
    }

    private func retainedSnapshotsUnlocked(from snapshots: [PasteboardSnapshot]) -> [PasteboardSnapshot] {
        var retained = snapshots
        let policy = HistoryRetentionPolicy(
            maximumCount: configuration.maximumHistoryCount,
            maximumDiskBytes: configuration.maximumDiskBytes
        )
        while retained.count > policy.maximumCount || storageBytesUnlocked(for: retained) > policy.maximumDiskBytes {
            guard let evictionIndex = retained.indices.reversed().first(where: {
                !protectedSnapshotIDs.contains(retained[$0].id)
            }) else {
                break
            }
            retained.remove(at: evictionIndex)
        }
        return retained
    }

    private func storageBytesUnlocked(for snapshots: [PasteboardSnapshot]) -> UInt64 {
        var references: [UUID: [HistoryStorageReference]] = [:]
        for snapshot in snapshots {
            var snapshotReferences: [HistoryStorageReference] = []
            for item in snapshot.items {
                for representation in item.representations where representation.status == .stored {
                    if let hash = representation.blobHash {
                        snapshotReferences.append(.blob(hash: hash, byteCount: representation.byteCount))
                    }
                }
                for file in item.fileSnapshots where file.status == .copied {
                    snapshotReferences.append(.file(byteCount: file.byteCount))
                }
            }
            references[snapshot.id] = snapshotReferences
        }
        return HistoryRetentionPolicy.storageBytes(for: snapshots.map(\.id), references: references)
    }

    private func removeUnreferencedBlobsUnlocked(from snapshots: [PasteboardSnapshot]) throws {
        let candidates = Self.referencedBlobHashes(in: snapshots)
        let referenced = Self.referencedBlobHashes(in: index.snapshots)
        _ = try blobStore.remove(hashes: candidates.subtracting(referenced))
    }

    private static func referencedBlobHashes(in snapshots: [PasteboardSnapshot]) -> Set<String> {
        Set(snapshots.flatMap { snapshot in
            snapshot.items.flatMap { item in
                item.representations.compactMap { representation in
                    representation.status == .stored ? representation.blobHash : nil
                }
            }
        })
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
