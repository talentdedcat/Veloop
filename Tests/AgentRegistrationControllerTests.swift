import Foundation
@testable import VeloopCore
import XCTest

final class AgentRegistrationControllerTests: XCTestCase {
    func testFreshRegistrationInstallsPersistentAgentBeforeWritingLaunchAgent() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.installedAgentExecutableURL.path))
        XCTAssertEqual(
            try Data(contentsOf: harness.installedAgentExecutableURL),
            Data("embedded-agent".utf8)
        )
        let data = try Data(contentsOf: harness.launchAgentURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            [harness.installedAgentExecutableURL.path]
        )
    }

    func testExistingPersistentAgentIsPreservedAcrossRegistration() throws {
        let harness = try makeHarness(
            statuses: [1, 0, 0, 0],
            installedAgentContents: "previous-authorized-agent"
        )

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(
            try Data(contentsOf: harness.installedAgentExecutableURL),
            Data("previous-authorized-agent".utf8)
        )
    }

    func testFreshRegistrationBootstrapsKickstartsVerifiesAndWritesStablePlist() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertEqual(harness.migration.callCount, 1)

        let data = try Data(contentsOf: harness.launchAgentURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, "com.veloop.service")
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], ["com.veloop.app"])
        XCTAssertEqual(
            plist["EnvironmentVariables"] as? [String: String],
            ["VELOOP_BUILD_VERSION": "test-build"]
        )
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            [harness.installedAgentExecutableURL.path]
        )
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["ProcessType"] as? String, "Interactive")
    }

    func testLoadedCurrentRegistrationStillKickstartsWithoutKThenVerifies() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0, 0, 0, 0])
        try harness.controller.ensureRegisteredAndRunning()
        harness.launchctl.removeCalls()

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertEqual(harness.migration.callCount, 1)
    }

    func testDisabledLoginBootstrapsKickstartsVerifiesThenRemovesPlist() throws {
        let harness = try makeHarness(startAtLogin: false, statuses: [1, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.launchAgentURL.path))
        XCTAssertFalse(harness.defaults.bool(forKey: "veloop.startAtLogin"))
    }

    func testRestartEnsuresWithNonKKickstartBeforeForcedKickstart() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0, 0])

        try harness.controller.restartRegisteredAgent()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
            ["kickstart", "-k", harness.serviceTarget],
        ])
    }

    func testKickstartFailurePropagatesAndRemovesDisabledLoginPlist() throws {
        let harness = try makeHarness(startAtLogin: false, statuses: [1, 0, 7])

        XCTAssertThrowsError(try harness.controller.ensureRegisteredAndRunning())

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.launchAgentURL.path))
    }

    func testPrintFailurePropagatesAndRemovesDisabledLoginPlist() throws {
        let harness = try makeHarness(startAtLogin: false, statuses: [1, 0, 0, 8])

        XCTAssertThrowsError(try harness.controller.ensureRegisteredAndRunning())

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.launchAgentURL.path))
    }

    func testLaunchctlFailureDoesNotPersistChangedLoginPreference() throws {
        let harness = try makeHarness(startAtLogin: false, statuses: [1, 9])

        XCTAssertThrowsError(try harness.controller.setStartAtLoginEnabled(true))

        XCTAssertFalse(harness.defaults.bool(forKey: "veloop.startAtLogin"))
        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
        ])
    }

    func testRapidPreferenceChangesPreserveSubmissionAndCompletionOrder() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0])
        let offCompleted = expectation(description: "off completed")
        let onCompleted = expectation(description: "on completed")
        let completions = CompletionRecorder()

        harness.controller.setStartAtLoginEnabled(false) { succeeded in
            completions.append("off:\(succeeded)")
            offCompleted.fulfill()
        }
        harness.controller.setStartAtLoginEnabled(true) { succeeded in
            completions.append("on:\(succeeded)")
            onCompleted.fulfill()
        }
        wait(for: [offCompleted, onCompleted], timeout: 1, enforceOrder: true)

        XCTAssertEqual(completions.values, ["off:true", "on:true"])
        XCTAssertTrue(harness.defaults.bool(forKey: "veloop.startAtLogin"))
        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
    }

    func testPreferenceReadDoesNotWaitForBlockedLifecycleLaunchctl() throws {
        let harness = try makeHarness(statuses: [1, 0, 0, 0], blockedLaunchctlCall: 0)
        let lifecycleFinished = DispatchSemaphore(value: 0)
        let preferenceReadFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            try? harness.controller.ensureRegisteredAndRunning()
            lifecycleFinished.signal()
        }
        XCTAssertEqual(
            harness.launchctl.blockedCallStarted.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            _ = harness.controller.isStartAtLoginEnabled
            preferenceReadFinished.signal()
        }
        let readBeforeRelease = preferenceReadFinished.wait(timeout: .now() + 1)

        harness.launchctl.releaseBlockedCall.signal()
        XCTAssertEqual(lifecycleFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(readBeforeRelease, .success)
    }

    private func makeHarness(
        startAtLogin: Bool? = nil,
        statuses: [Int32],
        blockedLaunchctlCall: Int? = nil,
        installedAgentContents: String? = nil
    ) throws -> RegistrationHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("veloop-registration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let suiteName = "veloop-registration-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        if let startAtLogin {
            defaults.set(startAtLogin, forKey: "veloop.startAtLogin")
        }

        let launchAgentURL = root
            .appendingPathComponent("Library/LaunchAgents/com.veloop.service.plist")
        let embeddedAgentBundleURL = root
            .appendingPathComponent("Embedded/Veloop.app")
        let embeddedAgentExecutableURL = embeddedAgentBundleURL
            .appendingPathComponent("Contents/MacOS/Veloop")
        try FileManager.default.createDirectory(
            at: embeddedAgentExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("embedded-agent".utf8).write(to: embeddedAgentExecutableURL)
        let installedAgentBundleURL = root
            .appendingPathComponent("Applications/Veloop Agent.app")
        let installedAgentExecutableURL = installedAgentBundleURL
            .appendingPathComponent("Contents/MacOS/Veloop")
        if let installedAgentContents {
            try FileManager.default.createDirectory(
                at: installedAgentExecutableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(installedAgentContents.utf8).write(to: installedAgentExecutableURL)
        }
        let launchctl = LaunchctlRecorder(
            statuses: statuses,
            blockedCall: blockedLaunchctlCall
        )
        let migration = MigrationRecorder()
        let controller = AgentRegistrationController(
            defaults: defaults,
            fileManager: .default,
            launchAgentURL: launchAgentURL,
            embeddedAgentBundleURL: embeddedAgentBundleURL,
            installedAgentBundleURL: installedAgentBundleURL,
            currentBuild: "test-build",
            unregisterLegacyService: { try migration.run() },
            launchctl: { arguments in try launchctl.run(arguments) }
        )
        let domainTarget = "gui/\(getuid())"
        return RegistrationHarness(
            controller: controller,
            defaults: defaults,
            launchAgentURL: launchAgentURL,
            installedAgentExecutableURL: installedAgentExecutableURL,
            launchctl: launchctl,
            migration: migration,
            domainTarget: domainTarget,
            serviceTarget: "\(domainTarget)/com.veloop.service"
        )
    }
}

private struct RegistrationHarness {
    let controller: AgentRegistrationController
    let defaults: UserDefaults
    let launchAgentURL: URL
    let installedAgentExecutableURL: URL
    let launchctl: LaunchctlRecorder
    let migration: MigrationRecorder
    let domainTarget: String
    let serviceTarget: String
}

private final class LaunchctlRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int32]
    private var storage: [[String]] = []
    private var callIndex = 0
    private let blockedCall: Int?
    let blockedCallStarted = DispatchSemaphore(value: 0)
    let releaseBlockedCall = DispatchSemaphore(value: 0)

    init(statuses: [Int32], blockedCall: Int? = nil) {
        self.statuses = statuses
        self.blockedCall = blockedCall
    }

    var calls: [[String]] {
        lock.withLock { storage }
    }

    func run(_ arguments: [String]) throws -> Int32 {
        let (status, shouldBlock) = try lock.withLock {
            storage.append(arguments)
            guard !statuses.isEmpty else { throw RegistrationTestError.unexpectedLaunchctlCall }
            defer { callIndex += 1 }
            return (statuses.removeFirst(), callIndex == blockedCall)
        }
        if shouldBlock {
            blockedCallStarted.signal()
            releaseBlockedCall.wait()
        }
        return status
    }

    func removeCalls() {
        lock.withLock { storage.removeAll() }
    }
}

private final class MigrationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func run() throws {
        lock.withLock { calls += 1 }
    }
}

private final class CompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private enum RegistrationTestError: Error {
    case unexpectedLaunchctlCall
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
