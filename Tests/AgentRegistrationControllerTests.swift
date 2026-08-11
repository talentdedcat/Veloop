import Foundation
import XCTest
@testable import VeloopCore

final class AgentRegistrationControllerTests: XCTestCase {
    func testFreshRegistrationCopiesCanonicalExecutableOutsideBundleAndUsesAgentMode() throws {
        let harness = try RegistrationHarness(statuses: [1, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()

        let plist = try harness.launchAgentPlist()
        XCTAssertEqual(plist["Label"] as? String, "com.veloop.service")
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], ["com.veloop.app"])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [
            harness.agentRuntimeExecutableURL.path,
            "--agent",
        ])
        XCTAssertEqual(
            try Data(contentsOf: harness.agentRuntimeExecutableURL),
            try Data(contentsOf: harness.executableURL)
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: harness.agentRuntimeExecutableURL.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: harness.agentRuntimeBundleURL.appendingPathComponent("Contents/Info.plist").path
        ))
        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["bootstrap", harness.domainTarget, harness.launchAgentURL.path],
            ["kickstart", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: harness.applicationsDirectory.appendingPathComponent("Veloop Agent.app").path
        ))
    }

    func testRegistrationRejectsWrongMainBundleIdentifierBeforeLaunchctl() throws {
        let harness = try RegistrationHarness(
            statuses: [],
            bundleIdentifier: "com.example.wrong"
        )

        XCTAssertThrowsError(try harness.controller.ensureRegisteredAndRunning())

        XCTAssertTrue(harness.launchctl.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.launchAgentURL.path))
    }

    func testLoadedUnresponsiveRegistrationIsForceKickstartedWithoutReplacingApplication() throws {
        let harness = try RegistrationHarness(statuses: [1, 0, 0, 0, 0, 0, 0])
        try harness.controller.ensureRegisteredAndRunning()
        harness.launchctl.removeCalls()

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["kickstart", "-k", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
        XCTAssertEqual(try Data(contentsOf: harness.executableURL), Data("main-executable".utf8))
    }

    func testPermissionRefreshAlwaysForceRestartsLoadedAgentAndWaitsForReadiness() throws {
        let harness = try RegistrationHarness(statuses: [1, 0, 0, 0, 0, 0, 0])
        try harness.controller.ensureRegisteredAndRunning()
        harness.launchctl.removeCalls()

        try harness.controller.restartForPermissionRefresh()

        XCTAssertEqual(harness.launchctl.calls, [
            ["print", harness.serviceTarget],
            ["kickstart", "-k", harness.serviceTarget],
            ["print", harness.serviceTarget],
        ])
    }

    func testDisabledLoginRunsCurrentAgentThenRemovesPersistentPlist() throws {
        let harness = try RegistrationHarness(startAtLogin: false, statuses: [1, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.launchAgentURL.path))
        XCTAssertFalse(harness.controller.isStartAtLoginEnabled)
    }

    func testLegacyServiceManagementMigrationRunsOnlyOnce() throws {
        let harness = try RegistrationHarness(statuses: [1, 0, 0, 0, 0, 0, 0])

        try harness.controller.ensureRegisteredAndRunning()
        try harness.controller.ensureRegisteredAndRunning()

        XCTAssertEqual(harness.legacyMigration.callCount, 1)
    }
}

private final class RegistrationHarness {
    let root: URL
    let applicationsDirectory: URL
    let appBundleURL: URL
    let executableURL: URL
    let agentRuntimeBundleURL: URL
    let agentRuntimeExecutableURL: URL
    let launchAgentURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let launchctl: RegistrationLaunchctlRecorder
    let legacyMigration = RegistrationCallRecorder()
    let controller: AgentRegistrationController
    let domainTarget = "gui/\(getuid())"
    var serviceTarget: String { "\(domainTarget)/com.veloop.service" }

    init(
        startAtLogin: Bool? = nil,
        statuses: [Int32],
        bundleIdentifier: String = "com.veloop.app"
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentRegistrationControllerTests-\(UUID().uuidString)")
        applicationsDirectory = root.appendingPathComponent("Applications", isDirectory: true)
        appBundleURL = applicationsDirectory.appendingPathComponent("Veloop.app", isDirectory: true)
        executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/Veloop")
        agentRuntimeBundleURL = root.appendingPathComponent(
            "home/Library/Application Support/Veloop/AgentRuntime/Veloop",
            isDirectory: true
        )
        agentRuntimeExecutableURL = agentRuntimeBundleURL.appendingPathComponent(
            "Contents/MacOS/Veloop"
        )
        launchAgentURL = root.appendingPathComponent(
            "home/Library/LaunchAgents/com.veloop.service.plist"
        )
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("main-executable".utf8).write(to: executableURL)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": "Veloop",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: appBundleURL.appendingPathComponent("Contents/Info.plist"))

        suiteName = "AgentRegistrationControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let startAtLogin {
            defaults.set(startAtLogin, forKey: "veloop.startAtLogin")
        }
        launchctl = RegistrationLaunchctlRecorder(statuses: statuses)
        let launchctl = self.launchctl
        let legacyMigration = self.legacyMigration
        controller = AgentRegistrationController(
            defaults: defaults,
            launchAgentURL: launchAgentURL,
            applicationBundleURL: appBundleURL,
            agentRuntimeBundleURL: agentRuntimeBundleURL,
            currentBuild: "test-build",
            unregisterLegacyService: { legacyMigration.increment() },
            launchctl: { arguments in try launchctl.run(arguments) }
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func launchAgentPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: launchAgentURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}

private final class RegistrationLaunchctlRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int32]
    private var storage: [[String]] = []

    init(statuses: [Int32]) {
        self.statuses = statuses
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func run(_ arguments: [String]) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        storage.append(arguments)
        guard !statuses.isEmpty else { throw RegistrationTestError.unexpectedLaunchctlCall }
        return statuses.removeFirst()
    }

    func removeCalls() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

private final class RegistrationCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func increment() {
        lock.lock()
        calls += 1
        lock.unlock()
    }
}

private enum RegistrationTestError: Error {
    case unexpectedLaunchctlCall
}
