import Foundation
import XCTest
@testable import VeloopCore

final class BlobStoreTests: XCTestCase {
    func testSaveAndRead() throws {
        let store = try makeStore()
        let data = Data("payload".utf8)

        let blob = try store.put(data)

        XCTAssertEqual(blob.hash, ContentHash.sha256(data))
        XCTAssertEqual(blob.byteCount, UInt64(data.count))
        XCTAssertEqual(try store.data(for: blob.hash), data)
    }

    func testSHA256DeduplicatesIdenticalData() throws {
        let store = try makeStore()
        let data = Data(repeating: 0x5a, count: 4096)

        let first = try store.put(data)
        let second = try store.put(data)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try store.allBlobHashes(), [first.hash])
    }

    func testZeroByteBlob() throws {
        let store = try makeStore()
        let blob = try store.put(Data())

        XCTAssertEqual(blob.byteCount, 0)
        XCTAssertEqual(try store.data(for: blob.hash), Data())
    }

    func testCorruptedBlobIsDetected() throws {
        let store = try makeStore()
        let blob = try store.put(Data("valid".utf8))
        try Data("tampered".utf8).write(to: store.url(for: blob.hash))

        XCTAssertThrowsError(try store.data(for: blob.hash)) { error in
            XCTAssertEqual(error as? BlobStoreError, .corrupted(blob.hash))
        }
    }

    func testConcurrentWritesOfSameBlob() throws {
        let store = try makeStore()
        let data = Data(repeating: 0xa5, count: 65_536)
        let lock = NSLock()
        var results: [StoredBlob] = []
        var errors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do {
                let blob = try store.put(data)
                lock.lock()
                results.append(blob)
                lock.unlock()
            } catch {
                lock.lock()
                errors.append(error)
                lock.unlock()
            }
        }

        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(Set(results.map(\.hash)), [ContentHash.sha256(data)])
        XCTAssertEqual(try store.allBlobHashes().count, 1)
    }

    func testGarbageCollectionRemovesOnlyUnreferencedBlobs() throws {
        let store = try makeStore()
        let kept = try store.put(Data("kept".utf8))
        let removed = try store.put(Data("removed".utf8))

        let result = try store.garbageCollect(referencedHashes: [kept.hash])

        XCTAssertEqual(result.removedHashes, [removed.hash])
        XCTAssertEqual(try store.data(for: kept.hash), Data("kept".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(for: removed.hash).path))
    }

    func testLargeFileUsesFileBackedInput() throws {
        let store = try makeStore()
        let source = store.rootURL.appendingPathComponent("large-input.bin")
        let chunk = Data(repeating: 0x42, count: 1_048_576)
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        for _ in 0..<8 {
            try handle.write(contentsOf: chunk)
        }
        try handle.close()

        let blob = try store.put(fileAt: source)

        XCTAssertEqual(blob.byteCount, 8_388_608)
        XCTAssertTrue(try store.validate(blob.hash))
    }

    func testAtomicWritesLeaveNoTemporaryFiles() throws {
        let store = try makeStore()
        _ = try store.put(Data("atomic".utf8))

        let temporaryFiles = try FileManager.default.subpathsOfDirectory(atPath: store.rootURL.path)
            .filter { $0.contains(".tmp-") || $0.contains(".incoming-") }
        XCTAssertTrue(temporaryFiles.isEmpty)
    }

    func testRejectsHashesThatAreNotCanonicalSHA256Values() throws {
        let store = try makeStore()
        let outside = store.rootURL.deletingLastPathComponent().appendingPathComponent("outside")
        try Data("sentinel".utf8).write(to: outside)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }

        for hash in [
            "../../outside",
            String(repeating: "A", count: 64),
            String(repeating: "a", count: 63),
            String(repeating: "z", count: 64),
        ] {
            XCTAssertThrowsError(try store.url(for: hash)) { error in
                XCTAssertEqual(error as? BlobStoreError, .invalidIdentifier(hash))
            }
            XCTAssertThrowsError(try store.data(for: hash)) { error in
                XCTAssertEqual(error as? BlobStoreError, .invalidIdentifier(hash))
            }
            XCTAssertThrowsError(try store.validate(hash)) { error in
                XCTAssertEqual(error as? BlobStoreError, .invalidIdentifier(hash))
            }
            XCTAssertThrowsError(try store.remove(hashes: [hash])) { error in
                XCTAssertEqual(error as? BlobStoreError, .invalidIdentifier(hash))
            }
        }
        XCTAssertEqual(try Data(contentsOf: outside), Data("sentinel".utf8))
    }

    func testReadRejectsBlobSymlinkEvenWhenTargetContentMatchesHash() throws {
        let store = try makeStore()
        let data = Data("outside".utf8)
        let blob = try store.put(data)
        let blobURL = try store.url(for: blob.hash)
        let outside = store.rootURL.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        try data.write(to: outside)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.removeItem(at: blobURL)
        try FileManager.default.createSymbolicLink(at: blobURL, withDestinationURL: outside)

        XCTAssertThrowsError(try store.data(for: blob.hash)) { error in
            XCTAssertEqual(error as? BlobStoreError, .corrupted(blob.hash))
        }
        XCTAssertFalse(try store.validate(blob.hash))
    }

    private func makeStore() throws -> BlobStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try BlobStore(rootURL: root)
    }
}
