import CryptoKit
import Darwin
import Foundation

struct StoredBlob: Codable, Equatable {
    let hash: String
    let byteCount: UInt64
}

struct BlobGarbageCollectionResult: Equatable {
    let removedHashes: [String]
    let removedBytes: UInt64
}

enum BlobStoreError: Error, Equatable {
    case invalidIdentifier(String)
    case missing(String)
    case corrupted(String)
}

final class BlobStore {
    let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let standardizedRoot = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: standardizedRoot, withIntermediateDirectories: true)
        self.rootURL = standardizedRoot.resolvingSymlinksInPath()
        try removeTemporaryFiles()
    }

    func put(_ data: Data) throws -> StoredBlob {
        let hash = ContentHash.sha256(data)
        let blob = StoredBlob(hash: hash, byteCount: UInt64(data.count))

        lock.lock()
        defer { lock.unlock() }
        if try isValidExistingBlob(blob) {
            return blob
        }

        let destination = try url(for: hash)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try validateShard(for: destination, hash: hash)
        try AtomicFileWriter.replace(data, at: destination)
        return blob
    }

    func put(fileAt source: URL) throws -> StoredBlob {
        let incoming = rootURL.appendingPathComponent(".incoming-\(UUID().uuidString)")
        fileManager.createFile(atPath: incoming.path, contents: nil)
        var hasher = SHA256()
        var byteCount: UInt64 = 0

        do {
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: incoming)
            defer {
                try? input.close()
                try? output.close()
            }

            while let chunk = try autoreleasepool(invoking: {
                try input.read(upToCount: 1_048_576)
            }), !chunk.isEmpty {
                hasher.update(data: chunk)
                byteCount += UInt64(chunk.count)
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
        } catch {
            try? fileManager.removeItem(at: incoming)
            throw error
        }

        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let blob = StoredBlob(hash: hash, byteCount: byteCount)

        lock.lock()
        defer { lock.unlock() }
        defer { try? fileManager.removeItem(at: incoming) }
        if try isValidExistingBlob(blob) {
            return blob
        }

        let destination = try url(for: hash)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try validateShard(for: destination, hash: hash)
        guard rename(incoming.path, destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        return blob
    }

    func data(for hash: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let location = try existingBlobURL(for: hash) else {
            throw BlobStoreError.missing(hash)
        }
        let data = try Data(contentsOf: location, options: [.mappedIfSafe])
        guard ContentHash.sha256(data) == hash else {
            throw BlobStoreError.corrupted(hash)
        }
        return data
    }

    func validate(_ hash: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ContentHash.isValidSHA256Identifier(hash) else {
            throw BlobStoreError.invalidIdentifier(hash)
        }
        let location: URL
        do {
            guard let existing = try existingBlobURL(for: hash) else { return false }
            location = existing
        } catch BlobStoreError.corrupted {
            return false
        }
        return try hashFile(at: location).hash == hash
    }

    func url(for hash: String) throws -> URL {
        guard ContentHash.isValidSHA256Identifier(hash) else {
            throw BlobStoreError.invalidIdentifier(hash)
        }
        let prefix = String(hash.prefix(2))
        return rootURL.appendingPathComponent(prefix, isDirectory: true).appendingPathComponent(hash)
    }

    func allBlobHashes() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return try allBlobHashesUnlocked()
    }

    func storedBytes() throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return try allBlobHashesUnlocked().reduce(0) { total, hash in
            let values = try url(for: hash).resourceValues(forKeys: [.fileSizeKey])
            return total + UInt64(values.fileSize ?? 0)
        }
    }

    func garbageCollect(referencedHashes: Set<String>) throws -> BlobGarbageCollectionResult {
        lock.lock()
        defer { lock.unlock() }
        return try removeUnlocked(hashes: Set(allBlobHashesUnlocked()).subtracting(referencedHashes))
    }

    func remove(hashes: Set<String>) throws -> BlobGarbageCollectionResult {
        lock.lock()
        defer { lock.unlock() }
        return try removeUnlocked(hashes: hashes)
    }

    private func removeUnlocked(hashes: Set<String>) throws -> BlobGarbageCollectionResult {
        var removedHashes: [String] = []
        var removedBytes: UInt64 = 0

        for hash in hashes.sorted() {
            let location = try url(for: hash)
            guard fileManager.fileExists(atPath: location.path) else {
                continue
            }
            guard (try? existingBlobURL(for: hash)) != nil else {
                throw BlobStoreError.corrupted(hash)
            }
            let values = try location.resourceValues(forKeys: [.fileSizeKey])
            removedBytes += UInt64(values.fileSize ?? 0)
            try fileManager.removeItem(at: location)
            removedHashes.append(hash)
        }
        return BlobGarbageCollectionResult(removedHashes: removedHashes.sorted(), removedBytes: removedBytes)
    }

    private func isValidExistingBlob(_ blob: StoredBlob) throws -> Bool {
        guard let destination = try existingBlobURL(for: blob.hash) else {
            return false
        }
        let existing = try hashFile(at: destination)
        if existing == blob {
            return true
        }
        try fileManager.removeItem(at: destination)
        return false
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
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return StoredBlob(hash: hash, byteCount: byteCount)
    }

    private func allBlobHashesUnlocked() throws -> [String] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        let shardURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var hashes: [String] = []
        for shard in shardURLs where shard.lastPathComponent.count == 2 {
            let values = try shard.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                continue
            }
            let entries = try fileManager.contentsOfDirectory(
                at: shard,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                let hash = entry.lastPathComponent
                let entryValues = try entry.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard ContentHash.isValidSHA256Identifier(hash),
                      hash.hasPrefix(shard.lastPathComponent),
                      entryValues.isRegularFile == true,
                      entryValues.isSymbolicLink != true else {
                    continue
                }
                hashes.append(hash)
            }
        }
        return hashes.sorted()
    }

    private func existingBlobURL(for hash: String) throws -> URL? {
        let location = try url(for: hash)
        guard fileManager.fileExists(atPath: location.path) else { return nil }
        let values = try location.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let resolved = location.resolvingSymlinksInPath()
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              contains(resolved) else {
            throw BlobStoreError.corrupted(hash)
        }
        return location
    }

    private func validateShard(for destination: URL, hash: String) throws {
        let shard = destination.deletingLastPathComponent()
        let values = try shard.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              contains(shard.resolvingSymlinksInPath()) else {
            throw BlobStoreError.corrupted(hash)
        }
    }

    private func contains(_ resolvedURL: URL) -> Bool {
        resolvedURL.path.hasPrefix(rootURL.path + "/")
    }

    private func removeTemporaryFiles() throws {
        let children = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        for name in children where name.hasPrefix(".incoming-") || name.hasPrefix(".tmp-") {
            try fileManager.removeItem(at: rootURL.appendingPathComponent(name))
        }
    }
}
