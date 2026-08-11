import Foundation
import XCTest
@testable import VeloopCore

final class VeloopCleanupControllerTests: XCTestCase {
    func testPreserveRemovesLegacySingleFileAndCurrentAgentRuntime() throws {
        let harness = try CleanupHarness()
        try FileManager.default.createDirectory(
            at: harness.paths.agentRuntimeDirectory,
            withIntermediateDirectories: true
        )
        try Data("legacy-agent".utf8).write(to: harness.paths.legacyAgentRuntimeBundle)
        try FileManager.default.createDirectory(
            at: harness.paths.agentRuntimeBundle,
            withIntermediateDirectories: true
        )

        try harness.controller.cleanup(scope: .preserveUserData, includeWatcher: false)

        XCTAssertFalse(harness.exists(harness.paths.legacyAgentRuntimeBundle))
        XCTAssertFalse(harness.exists(harness.paths.agentRuntimeBundle))
        XCTAssertFalse(harness.exists(harness.paths.agentRuntimeDirectory))
    }

    func testPreserveRemovesPermissionsAndRuntimeButKeepsUserData() throws {
        let harness = try CleanupHarness()
        try harness.populateAllPaths()

        try harness.controller.cleanup(scope: .preserveUserData, includeWatcher: true)

        XCTAssertEqual(harness.permissionResetter.callCount, 1)
        XCTAssertEqual(harness.paletteTerminationCount, 1)
        for url in harness.paths.functionalRuntimePaths + harness.paths.watcherPaths {
            XCTAssertFalse(harness.exists(url), url.path)
        }
        for url in harness.paths.userDataPaths {
            XCTAssertTrue(harness.exists(url), url.path)
        }
        XCTAssertTrue(harness.exists(harness.paths.applicationSupportRoot))
    }

    func testPurgeRemovesEveryKnownPath() throws {
        let harness = try CleanupHarness()
        try harness.populateAllPaths()

        try harness.controller.cleanup(scope: .purgeUserData, includeWatcher: true)

        XCTAssertEqual(harness.permissionResetter.callCount, 1)
        for url in harness.paths.allKnownPaths {
            XCTAssertFalse(harness.exists(url), url.path)
        }
    }

    func testPermissionFailureKeepsWatcherForRetry() throws {
        let harness = try CleanupHarness(permissionError: TestError.permissionResetFailed)
        try harness.populateAllPaths()

        XCTAssertThrowsError(
            try harness.controller.cleanup(scope: .purgeUserData, includeWatcher: true)
        )

        XCTAssertTrue(harness.exists(harness.paths.watcherExecutable))
        XCTAssertTrue(harness.exists(harness.paths.watcherLaunchAgent))
        XCTAssertTrue(harness.exists(harness.paths.configuration))
    }

    func testLoadedAgentMustBootOutSuccessfullyBeforeReset() throws {
        let harness = try CleanupHarness(launchctlStatus: { arguments in
            arguments.first == "print" ? 0 : 5
        })
        try harness.populateAllPaths()

        XCTAssertThrowsError(
            try harness.controller.cleanup(scope: .preserveUserData, includeWatcher: true)
        )
        XCTAssertEqual(harness.permissionResetter.callCount, 0)
        XCTAssertTrue(harness.exists(harness.paths.watcherExecutable))
    }
}

private enum TestError: Error {
    case permissionResetFailed
}

private final class PermissionResetRecorder: TCCPermissionResetting, @unchecked Sendable {
    private let error: Error?
    private(set) var callCount = 0

    init(error: Error?) {
        self.error = error
    }

    func resetVeloopPermissions() throws {
        callCount += 1
        if let error { throw error }
    }
}

private final class CleanupHarness {
    let root: URL
    let paths: VeloopCleanupPaths
    let permissionResetter: PermissionResetRecorder
    let controller: VeloopCleanupController
    private let paletteCounter = Counter()
    var paletteTerminationCount: Int { paletteCounter.value }

    init(
        permissionError: Error? = nil,
        launchctlStatus: @escaping @Sendable ([String]) -> Int32 = { _ in 1 }
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VeloopCleanupControllerTests-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        paths = VeloopCleanupPaths(homeDirectory: home, applicationsDirectory: applications)
        permissionResetter = PermissionResetRecorder(error: permissionError)
        let paletteCounter = self.paletteCounter
        controller = VeloopCleanupController(
            paths: paths,
            permissionResetter: permissionResetter,
            launchctl: launchctlStatus,
            terminatePalette: { paletteCounter.increment() }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func populateAllPaths() throws {
        for url in Set(paths.functionalRuntimePaths + paths.watcherPaths + paths.userDataPaths) {
            try createFile(at: url)
        }
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if url == paths.watcherDirectory
            || url == paths.agentRuntimeDirectory
            || url == paths.agentRuntimeBundle
            || url == paths.legacyAgentRuntimeBundle {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8)))
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
