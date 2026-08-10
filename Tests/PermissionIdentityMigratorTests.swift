import Foundation
import XCTest
@testable import VeloopCore

final class PermissionIdentityMigratorTests: XCTestCase {
    func testMissingReceiptRunsCleanupThenStoresCurrentHash() throws {
        let harness = try MigrationHarness(executableContents: "current")

        try harness.migrator.migrateIfNeeded()

        XCTAssertEqual(harness.cleanup.callCount, 1)
        XCTAssertEqual(
            try harness.receipt().executableSHA256,
            ContentHash.sha256(Data("current".utf8))
        )
    }

    func testChangedHashRunsCleanupThenReplacesReceipt() throws {
        let harness = try MigrationHarness(executableContents: "current")
        try harness.writeReceipt(hash: ContentHash.sha256(Data("old".utf8)))

        try harness.migrator.migrateIfNeeded()

        XCTAssertEqual(harness.cleanup.callCount, 1)
        XCTAssertEqual(
            try harness.receipt().executableSHA256,
            ContentHash.sha256(Data("current".utf8))
        )
    }

    func testMatchingHashSkipsCleanup() throws {
        let harness = try MigrationHarness(executableContents: "current")
        try harness.writeReceipt(hash: ContentHash.sha256(Data("current".utf8)))

        try harness.migrator.migrateIfNeeded()

        XCTAssertEqual(harness.cleanup.callCount, 0)
    }

    func testFailedCleanupDoesNotWriteReceipt() throws {
        let harness = try MigrationHarness(
            executableContents: "current",
            cleanupError: MigrationTestError.cleanupFailed
        )

        XCTAssertThrowsError(try harness.migrator.migrateIfNeeded())

        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.receiptURL.path))
    }

    func testUnreadableExecutableDoesNotWriteReceipt() throws {
        let harness = try MigrationHarness(executableContents: nil)

        XCTAssertThrowsError(try harness.migrator.migrateIfNeeded())

        XCTAssertEqual(harness.cleanup.callCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.receiptURL.path))
    }
}

private enum MigrationTestError: Error {
    case cleanupFailed
}

private final class MigrationCleanupRecorder: @unchecked Sendable {
    private let error: Error?
    private(set) var callCount = 0

    init(error: Error?) {
        self.error = error
    }

    func run() throws {
        callCount += 1
        if let error { throw error }
    }
}

private final class MigrationHarness {
    let root: URL
    let executableURL: URL
    let receiptURL: URL
    let cleanup: MigrationCleanupRecorder
    let migrator: PermissionIdentityMigrator

    init(executableContents: String?, cleanupError: Error? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionIdentityMigratorTests-\(UUID().uuidString)")
        executableURL = root.appendingPathComponent("Veloop")
        receiptURL = root.appendingPathComponent("state/permission-identity.json")
        cleanup = MigrationCleanupRecorder(error: cleanupError)
        if let executableContents {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(executableContents.utf8).write(to: executableURL)
        }
        let cleanup = self.cleanup
        migrator = PermissionIdentityMigrator(
            executableURL: executableURL,
            receiptURL: receiptURL,
            cleanup: { try cleanup.run() }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeReceipt(hash: String) throws {
        try FileManager.default.createDirectory(
            at: receiptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(
            PermissionIdentityReceipt(executableSHA256: hash)
        ).write(to: receiptURL)
    }

    func receipt() throws -> PermissionIdentityReceipt {
        try JSONDecoder().decode(
            PermissionIdentityReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
    }
}
