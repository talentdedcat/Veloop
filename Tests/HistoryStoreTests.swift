import Foundation
import XCTest
@testable import VeloopCore

final class HistoryStoreTests: XCTestCase {
    func testAddsRecordsNewestFirst() throws {
        let fixture = try makeFixture()
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")

        XCTAssertEqual(try fixture.store.add(first), .inserted(first.id))
        XCTAssertEqual(try fixture.store.add(second), .inserted(second.id))

        XCTAssertEqual(fixture.store.snapshotIDs(), [second.id, first.id])
        XCTAssertEqual(fixture.store.count, 2)
    }

    func testDuplicateFullSnapshotMovesExistingRecordToFront() throws {
        let fixture = try makeFixture()
        let first = try fixture.snapshot("repeat")
        let second = try fixture.snapshot("other")
        let duplicate = try fixture.snapshot("repeat")
        try fixture.store.add(first)
        try fixture.store.add(second)

        XCTAssertEqual(try fixture.store.add(duplicate), .movedExisting(first.id))

        XCTAssertEqual(fixture.store.snapshotIDs(), [first.id, second.id])
        XCTAssertEqual(fixture.store.count, 2)
    }

    func testCountLimitEvictsLeastRecentlyUsed() throws {
        let fixture = try makeFixture(maximumHistoryCount: 2)
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")
        let third = try fixture.snapshot("third")
        try fixture.store.add(first)
        try fixture.store.add(second)

        let result = try fixture.store.add(third)

        XCTAssertEqual(result, .inserted(third.id))
        XCTAssertEqual(fixture.store.snapshotIDs(), [third.id, second.id])
        XCTAssertNil(fixture.store.snapshot(id: first.id))
    }

    func testDiskLimitEvictsLeastRecentlyUsed() throws {
        let fixture = try makeFixture(maximumDiskBytes: 8)
        let first = try fixture.snapshot("123456")
        let second = try fixture.snapshot("abcdef")
        try fixture.store.add(first)

        try fixture.store.add(second)

        XCTAssertEqual(fixture.store.snapshotIDs(), [second.id])
        XCTAssertLessThanOrEqual(fixture.store.storageBytes, 8)
    }

    func testSuccessfulUseRefreshesLRUOrderBeforeQuotaEviction() throws {
        let fixture = try makeFixture(maximumHistoryCount: 2)
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")
        let third = try fixture.snapshot("third")
        try fixture.store.add(first)
        try fixture.store.add(second)

        XCTAssertTrue(try fixture.store.markRecentlyUsed(first.id))
        try fixture.store.add(third)

        XCTAssertEqual(fixture.store.snapshotIDs(), [third.id, first.id])
        XCTAssertNil(fixture.store.snapshot(id: second.id))
    }

    func testLRUOrderPersistsAcrossStoreReopen() throws {
        let fixture = try makeFixture()
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")
        try fixture.store.add(first)
        try fixture.store.add(second)
        try fixture.store.markRecentlyUsed(first.id)

        let reopened = try HistoryStore(
            paths: fixture.paths,
            configuration: fixture.configuration
        )

        XCTAssertEqual(reopened.snapshotIDs(), [first.id, second.id])
    }

    func testSingleOversizeSnapshotIsRejected() throws {
        let fixture = try makeFixture(maximumSingleSnapshotBytes: 3)
        let snapshot = try fixture.snapshot("four")

        XCTAssertEqual(try fixture.store.add(snapshot), .rejectedOversize(snapshot.id))
        XCTAssertEqual(fixture.store.count, 0)
    }

    func testLeasedSnapshotIsNotEvicted() throws {
        let fixture = try makeFixture(maximumHistoryCount: 1)
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")
        try fixture.store.add(first)
        let lease = try XCTUnwrap(fixture.store.acquireLease(for: first.id))

        try fixture.store.add(second)

        XCTAssertEqual(fixture.store.snapshotIDs(), [first.id])
        lease.release()
    }

    func testGarbageCollectionKeepsReferencedBlob() throws {
        let fixture = try makeFixture(maximumHistoryCount: 1)
        let first = try fixture.snapshot("first")
        let second = try fixture.snapshot("second")
        try fixture.store.add(first)
        try fixture.store.add(second)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try fixture.blobStore.url(
                for: first.items[0].representations[0].blobHash!
            ).path
        ))
        XCTAssertTrue(try fixture.blobStore.validate(second.items[0].representations[0].blobHash!))
    }

    func testCorruptHistoryManifestRecoversEmpty() throws {
        let root = try temporaryDirectory()
        let paths = StoragePaths(root: root)
        try paths.createDirectories()
        try Data("broken".utf8).write(to: paths.history)

        let store = try HistoryStore(paths: paths, configuration: .default)

        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.corrupted.path).count, 1)
    }

    private func makeFixture(
        maximumHistoryCount: Int = 100,
        maximumDiskBytes: UInt64 = 5_368_709_120,
        maximumSingleSnapshotBytes: UInt64 = 2_147_483_648
    ) throws -> Fixture {
        let root = try temporaryDirectory()
        let paths = StoragePaths(root: root)
        try paths.createDirectories()
        var configuration = Configuration.default
        configuration.maximumHistoryCount = maximumHistoryCount
        configuration.maximumDiskBytes = maximumDiskBytes
        configuration.maximumSingleSnapshotBytes = maximumSingleSnapshotBytes
        let blobStore = try BlobStore(rootURL: paths.blobs)
        return Fixture(
            store: try HistoryStore(paths: paths, configuration: configuration, blobStore: blobStore),
            blobStore: blobStore,
            paths: paths,
            configuration: configuration
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private struct Fixture {
        let store: HistoryStore
        let blobStore: BlobStore
        let paths: StoragePaths
        let configuration: Configuration

        func snapshot(_ value: String) throws -> PasteboardSnapshot {
            let data = Data(value.utf8)
            let blob = try blobStore.put(data)
            return PasteboardSnapshot(
                id: UUID(),
                createdAt: Date(),
                changeCount: Int.random(in: 1...10_000),
                items: [PasteboardItemSnapshot(index: 0, representations: [
                    PasteboardRepresentation(
                        typeIdentifier: "public.utf8-plain-text",
                        blobHash: blob.hash,
                        byteCount: blob.byteCount,
                        status: .stored,
                        errorIdentifier: nil
                    )
                ])],
                captureStatus: .complete
            )
        }
    }
}
