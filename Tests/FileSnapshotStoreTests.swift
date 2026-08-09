import Foundation
import XCTest
@testable import VeloopCore

final class FileSnapshotStoreTests: XCTestCase {
    func testCopiesFileAndReturnsRestorableURL() throws {
        let fixture = try makeFixture()
        let source = fixture.source.appendingPathComponent("movie.mov")
        try Data(repeating: 0x4d, count: 1024).write(to: source)

        let reference = fixture.store.snapshot(
            sourceURL: source,
            snapshotID: fixture.snapshotID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url"
        )

        XCTAssertEqual(reference.status, .copied)
        XCTAssertEqual(reference.byteCount, 1024)
        XCTAssertFalse(reference.isDirectory)
        let restored = try XCTUnwrap(fixture.store.restoredURL(for: reference))
        XCTAssertEqual(try Data(contentsOf: restored), Data(repeating: 0x4d, count: 1024))
    }

    func testRecursivelyCopiesFolder() throws {
        let fixture = try makeFixture()
        let folder = fixture.source.appendingPathComponent("Folder", isDirectory: true)
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: nested.appendingPathComponent("note.txt"))

        let reference = fixture.store.snapshot(
            sourceURL: folder,
            snapshotID: fixture.snapshotID,
            itemIndex: 1,
            ordinal: 0,
            typeIdentifier: "public.file-url"
        )

        XCTAssertEqual(reference.status, .copied)
        XCTAssertTrue(reference.isDirectory)
        let restored = try XCTUnwrap(fixture.store.restoredURL(for: reference))
        XCTAssertEqual(try String(contentsOf: restored.appendingPathComponent("Nested/note.txt"), encoding: .utf8), "inside")
    }

    func testDuplicateNamesUseDistinctItemSlots() throws {
        let fixture = try makeFixture()
        let firstDirectory = fixture.source.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = fixture.source.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let first = firstDirectory.appendingPathComponent("same.txt")
        let second = secondDirectory.appendingPathComponent("same.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let firstReference = fixture.store.snapshot(sourceURL: first, snapshotID: fixture.snapshotID, itemIndex: 0, ordinal: 0, typeIdentifier: "public.file-url")
        let secondReference = fixture.store.snapshot(sourceURL: second, snapshotID: fixture.snapshotID, itemIndex: 1, ordinal: 0, typeIdentifier: "public.file-url")

        XCTAssertNotEqual(firstReference.relativePath, secondReference.relativePath)
        XCTAssertNotEqual(firstReference.contentHash, secondReference.contentHash)
    }

    func testMissingSourceRecordsFailure() throws {
        let fixture = try makeFixture()
        let missing = fixture.source.appendingPathComponent("missing.bin")

        let reference = fixture.store.snapshot(sourceURL: missing, snapshotID: fixture.snapshotID, itemIndex: 0, ordinal: 0, typeIdentifier: "public.file-url")

        XCTAssertEqual(reference.status, .sourceMissing)
        XCTAssertNil(reference.relativePath)
        XCTAssertNil(reference.contentHash)
        XCTAssertEqual(reference.errorIdentifier, "source-missing")
    }

    func testRemoveSnapshotDeletesItsObjectDirectory() throws {
        let fixture = try makeFixture()
        let source = fixture.source.appendingPathComponent("file.dat")
        try Data([1, 2, 3]).write(to: source)
        let reference = fixture.store.snapshot(sourceURL: source, snapshotID: fixture.snapshotID, itemIndex: 0, ordinal: 0, typeIdentifier: "public.file-url")
        XCTAssertNotNil(fixture.store.restoredURL(for: reference))

        try fixture.store.removeSnapshot(fixture.snapshotID)

        XCTAssertNil(fixture.store.restoredURL(for: reference))
    }

    func testRejectsOversizeFileBeforeCopyingIt() throws {
        let fixture = try makeFixture()
        let source = fixture.source.appendingPathComponent("large.dat")
        try Data(repeating: 0x7f, count: 4096).write(to: source)

        let reference = fixture.store.snapshot(
            sourceURL: source,
            snapshotID: fixture.snapshotID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url",
            maximumBytes: 1024
        )

        XCTAssertEqual(reference.status, .tooLarge)
        XCTAssertGreaterThan(reference.byteCount, 1024)
        XCTAssertNil(fixture.store.restoredURL(for: reference))
        XCTAssertEqual(try fixture.store.storedBytes(), 0)
    }

    func testRejectsOversizeFolderBeforeCopyingIt() throws {
        let fixture = try makeFixture()
        let folder = fixture.source.appendingPathComponent("large-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x7f, count: 4096).write(to: folder.appendingPathComponent("large.dat"))

        let reference = fixture.store.snapshot(
            sourceURL: folder,
            snapshotID: fixture.snapshotID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url",
            maximumBytes: 1024
        )

        XCTAssertEqual(reference.status, .tooLarge)
        XCTAssertEqual(try fixture.store.storedBytes(), 0)
    }

    func testGarbageCollectionRemovesOnlyUnreferencedSnapshotDirectories() throws {
        let fixture = try makeFixture()
        let source = fixture.source.appendingPathComponent("file.dat")
        try Data([1, 2, 3]).write(to: source)
        let retainedID = UUID()
        let removedID = UUID()
        let retained = fixture.store.snapshot(
            sourceURL: source,
            snapshotID: retainedID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url"
        )
        let removed = fixture.store.snapshot(
            sourceURL: source,
            snapshotID: removedID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url"
        )

        try fixture.store.garbageCollectUnreferencedSnapshots(referencedIDs: [retainedID])

        XCTAssertNotNil(fixture.store.restoredURL(for: retained))
        XCTAssertNil(fixture.store.restoredURL(for: removed))
    }

    func testRestoredURLRejectsSymlinkThatEscapesStorageRoot() throws {
        let fixture = try makeFixture()
        let source = fixture.source.appendingPathComponent("secret.txt")
        try Data("inside".utf8).write(to: source)
        let reference = fixture.store.snapshot(
            sourceURL: source,
            snapshotID: fixture.snapshotID,
            itemIndex: 0,
            ordinal: 0,
            typeIdentifier: "public.file-url"
        )
        let restored = try XCTUnwrap(fixture.store.restoredURL(for: reference))
        let outside = fixture.source.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: restored)
        try FileManager.default.createSymbolicLink(at: restored, withDestinationURL: outside)

        XCTAssertNil(fixture.store.restoredURL(for: reference))
    }

    private func makeFixture() throws -> (store: FileSnapshotStore, source: URL, snapshotID: UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let files = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try FileSnapshotStore(rootURL: files), source, UUID())
    }
}
