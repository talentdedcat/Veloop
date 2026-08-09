import CryptoKit
import Foundation

final class FileSnapshotStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let standardizedRoot = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: standardizedRoot, withIntermediateDirectories: true)
        self.rootURL = standardizedRoot.resolvingSymlinksInPath()
    }

    func snapshot(
        sourceURL: URL,
        snapshotID: UUID,
        itemIndex: Int,
        ordinal: Int,
        typeIdentifier: String,
        maximumBytes: UInt64 = .max
    ) -> FileSnapshotReference {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            return failureReference(
                itemIndex: itemIndex,
                ordinal: ordinal,
                typeIdentifier: typeIdentifier,
                status: .sourceMissing,
                errorIdentifier: "source-missing"
            )
        }

        do {
            let sourceBytes = try storedByteCount(
                at: sourceURL,
                isDirectory: isDirectory.boolValue,
                stoppingAfter: maximumBytes
            )
            guard sourceBytes <= maximumBytes else {
                return failureReference(
                    itemIndex: itemIndex,
                    ordinal: ordinal,
                    typeIdentifier: typeIdentifier,
                    byteCount: sourceBytes,
                    status: .tooLarge,
                    errorIdentifier: "source-too-large"
                )
            }
        } catch {
            return failureReference(
                itemIndex: itemIndex,
                ordinal: ordinal,
                typeIdentifier: typeIdentifier,
                status: .copyFailed,
                errorIdentifier: "source-size-failed"
            )
        }

        lock.lock()
        defer { lock.unlock() }
        let slot = rootURL
            .appendingPathComponent(snapshotID.uuidString, isDirectory: true)
            .appendingPathComponent(String(itemIndex), isDirectory: true)
            .appendingPathComponent(String(ordinal), isDirectory: true)
        let destination = slot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: isDirectory.boolValue)

        do {
            try fileManager.createDirectory(at: slot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            let identity = try contentIdentity(at: destination, isDirectory: isDirectory.boolValue)
            guard identity.byteCount <= maximumBytes else {
                try fileManager.removeItem(at: slot)
                return failureReference(
                    itemIndex: itemIndex,
                    ordinal: ordinal,
                    typeIdentifier: typeIdentifier,
                    byteCount: identity.byteCount,
                    status: .tooLarge,
                    errorIdentifier: "source-too-large"
                )
            }
            let relativePath = destination.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            return FileSnapshotReference(
                itemIndex: itemIndex,
                ordinal: ordinal,
                originalTypeIdentifier: typeIdentifier,
                relativePath: relativePath,
                contentHash: identity.hash,
                byteCount: identity.byteCount,
                isDirectory: isDirectory.boolValue,
                status: .copied,
                errorIdentifier: nil
            )
        } catch {
            try? fileManager.removeItem(at: slot)
            return failureReference(
                itemIndex: itemIndex,
                ordinal: ordinal,
                typeIdentifier: typeIdentifier,
                status: .copyFailed,
                errorIdentifier: "copy-failed"
            )
        }
    }

    func restoredURL(for reference: FileSnapshotReference) -> URL? {
        guard reference.status == .copied, let relativePath = reference.relativePath else {
            return nil
        }
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(rootPath), fileManager.fileExists(atPath: candidate.path) else {
            return nil
        }
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard resolvedCandidate.path.hasPrefix(rootPath) else {
            return nil
        }
        return resolvedCandidate
    }

    func removeSnapshot(_ snapshotID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        let directory = rootURL.appendingPathComponent(snapshotID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func garbageCollectUnreferencedSnapshots(referencedIDs: Set<UUID>) throws {
        lock.lock()
        defer { lock.unlock() }
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for child in children {
            guard let snapshotID = UUID(uuidString: child.lastPathComponent),
                  !referencedIDs.contains(snapshotID) else {
                continue
            }
            try fileManager.removeItem(at: child)
        }
    }

    func storedBytes() throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else {
            return 0
        }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            total += try autoreleasepool {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                return values.isRegularFile == true ? UInt64(values.fileSize ?? 0) : 0
            }
        }
        return total
    }

    private func failureReference(
        itemIndex: Int,
        ordinal: Int,
        typeIdentifier: String,
        byteCount: UInt64 = 0,
        status: FileSnapshotStatus,
        errorIdentifier: String
    ) -> FileSnapshotReference {
        FileSnapshotReference(
            itemIndex: itemIndex,
            ordinal: ordinal,
            originalTypeIdentifier: typeIdentifier,
            relativePath: nil,
            contentHash: nil,
            byteCount: byteCount,
            isDirectory: false,
            status: status,
            errorIdentifier: errorIdentifier
        )
    }

    private func storedByteCount(
        at url: URL,
        isDirectory: Bool,
        stoppingAfter maximumBytes: UInt64
    ) throws -> UInt64 {
        guard isDirectory else {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(max(0, values.fileSize ?? 0))
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: UInt64 = 0
        for case let entry as URL in enumerator {
            let byteCount = try autoreleasepool {
                let values = try entry.resourceValues(forKeys: Set(keys))
                return values.isRegularFile == true ? UInt64(max(0, values.fileSize ?? 0)) : 0
            }
            let (updated, overflow) = total.addingReportingOverflow(byteCount)
            total = overflow ? .max : updated
            if total > maximumBytes {
                return total
            }
        }
        return total
    }

    private func contentIdentity(at url: URL, isDirectory: Bool) throws -> StoredBlob {
        if !isDirectory {
            return try hashFile(at: url)
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return StoredBlob(hash: ContentHash.sha256(Data()), byteCount: 0)
        }
        let entries = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        for entry in entries {
            try autoreleasepool {
                let relativePath = entry.path.replacingOccurrences(of: url.path + "/", with: "")
                update(relativePath, hasher: &hasher)
                let values = try entry.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true {
                    update("directory", hasher: &hasher)
                } else if values.isSymbolicLink == true {
                    update("symlink", hasher: &hasher)
                    update(try fileManager.destinationOfSymbolicLink(atPath: entry.path), hasher: &hasher)
                } else if values.isRegularFile == true {
                    update("file", hasher: &hasher)
                    let file = try hashFile(at: entry)
                    update(file.hash, hasher: &hasher)
                    byteCount += file.byteCount
                }
            }
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return StoredBlob(hash: hash, byteCount: byteCount)
    }

    private func hashFile(at url: URL) throws -> StoredBlob {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        while let chunk = try autoreleasepool(invoking: {
            try handle.read(upToCount: 1_048_576)
        }), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += UInt64(chunk.count)
        }
        return StoredBlob(
            hash: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            byteCount: byteCount
        )
    }

    private func update(_ value: String, hasher: inout SHA256) {
        let data = Data(value.utf8)
        var count = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }
}
