import Foundation
import XCTest

final class AppLifecycleSourceContractTests: XCTestCase {
    func testAppDelegateInjectsLifecycleWithoutSynchronousOrSwallowedRegistration() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let launch = try functionBody(named: "applicationDidFinishLaunching", in: delegate)
        let activation = try functionBody(named: "applicationDidBecomeActive", in: delegate)

        XCTAssertTrue(delegate.contains("let viewModel = ControlViewModel("))
        XCTAssertTrue(delegate.contains("agent: agent"))
        XCTAssertTrue(delegate.contains("lifecycle: agentRegistrationController"))
        XCTAssertFalse(delegate.contains("try?"))
        XCTAssertFalse(delegate.contains("ensureRegistered"))
        XCTAssertTrue(launch.contains("Task { await viewModel.synchronizeOnLaunch() }"))
        XCTAssertFalse(launch.contains("applicationDidBecomeActive"))
        XCTAssertTrue(activation.contains("Task { await viewModel.applicationDidBecomeActive() }"))
        XCTAssertFalse(activation.contains("synchronizeOnLaunch"))
    }

    func testAppInstallsUninstallWatcherAfterIdentityMigrationBeforeDisplayingWindow() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let launch = try functionBody(named: "applicationDidFinishLaunching", in: delegate)
        let migration = try XCTUnwrap(launch.range(of: "try migrator.migrateIfNeeded()"))
        let watcher = try XCTUnwrap(launch.range(of: "try UninstallWatcherInstaller("))
        let palette = try XCTUnwrap(launch.range(of: "ensurePaletteInstalled()"))
        let window = try XCTUnwrap(launch.range(of: "controller.showWindow(nil)"))

        XCTAssertLessThan(migration.lowerBound, watcher.lowerBound)
        XCTAssertLessThan(watcher.lowerBound, palette.lowerBound)
        XCTAssertLessThan(palette.lowerBound, window.lowerBound)
        XCTAssertTrue(launch.contains("Contents/Resources/VeloopUninstallWatcher"))
        XCTAssertTrue(launch.contains("alert.runModal()"))
    }

    func testPaletteDefersCurrentInstallCleanupToPlainWatcher() throws {
        let palette = try text("Sources/Palette/main.m")

        XCTAssertTrue(palette.contains("VeloopUninstallWatcherPath()"))
        XCTAssertTrue(palette.contains("com.veloop.uninstall-watcher"))
        XCTAssertTrue(palette.contains("Library/LaunchAgents/com.veloop.uninstall-watcher.plist"))
        XCTAssertTrue(palette.contains("stringByAppendingPathComponent:@\"UninstallWatcher\""))
    }

    func testModelQueriesFirstThenRecoversExactlyOnceWithoutPolling() throws {
        let model = try text("Sources/Core/Control/ControlViewModel.swift")
        let synchronization = try functionBody(named: "synchronizeAllowingRecovery", in: model)
        let fastState = try XCTUnwrap(synchronization.range(of: "try agent.state()"))
        let recovery = try XCTUnwrap(
            synchronization.range(of: "try lifecycle.ensureRegisteredAndRunning()")
        )
        let recoveredState = try XCTUnwrap(
            synchronization.range(of: "let recoveredState")
        )

        XCTAssertLessThan(fastState.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, recoveredState.lowerBound)
        XCTAssertEqual(synchronization.components(separatedBy: "try agent.state()").count - 1, 2)
        XCTAssertFalse(model.contains("Task.sleep"))
        XCTAssertFalse(model.contains("retryPolicy"))
        XCTAssertFalse(model.contains("restartRegisteredAgent"))
        XCTAssertTrue(model.contains("restartAgentForPermissionRefresh"))
        XCTAssertTrue(model.contains("!permissions.canCycle"))
        XCTAssertFalse(model.contains("permissionRefreshPending"))
        XCTAssertTrue(synchronization.contains("publishFailure(.agentUnavailable"))
        XCTAssertFalse(model.contains("convenience init(agent:"))
        XCTAssertFalse(model.contains("CompatibilityAgentLifecycle"))
    }

    func testControllerSerializesMutationsWithoutBlockingPreferenceReads() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")

        XCTAssertTrue(registration.contains(
            "final class AgentRegistrationController: AgentLifecycleControlling, @unchecked Sendable"
        ))
        XCTAssertTrue(registration.contains(
            "typealias Launchctl = @Sendable ([String]) throws -> Int32"
        ))
        XCTAssertTrue(registration.contains(
            "typealias UnregisterLegacyService = @Sendable () throws -> Void"
        ))
        XCTAssertTrue(registration.contains("private let lock = NSLock()"))
        let preferenceRead = try functionOrPropertyBody(
            named: "isStartAtLoginEnabled",
            in: registration
        )
        XCTAssertFalse(preferenceRead.contains("lock.withLock"))
        for method in [
            "ensureRegisteredAndRunning",
            "setStartAtLoginEnabled",
        ] {
            let body = try functionOrPropertyBody(named: method, in: registration)
            XCTAssertTrue(body.contains("lock.withLock"), "\(method) must be serialized")
        }
    }

    func testDisabledLoginStillBootstrapsCurrentAgentBeforeRemovingPlist() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let ensure = try functionBody(named: "ensureRegisteredAndRunningLocked", in: registration)
        let install = try XCTUnwrap(ensure.range(of: "installLaunchAgent()"))
        let preference = try XCTUnwrap(ensure.range(
            of: "let shouldRemoveLaunchAgent = !startAtLoginPreference"
        ))
        let removal = try XCTUnwrap(ensure.range(of: "removeLaunchAgentFile()"))

        XCTAssertLessThan(preference.lowerBound, install.lowerBound)
        XCTAssertLessThan(install.lowerBound, removal.lowerBound)

        let installation = try functionBody(named: "installLaunchAgent", in: registration)
        XCTAssertTrue(installation.contains(
            "requireSuccess([\"bootstrap\", domainTarget, launchAgentURL.path])"
        ))
    }

    func testEnsureForceKickstartsOnlyLoadedUnresponsiveAgentThenWaitsForReadiness() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let ensure = try functionBody(named: "ensureRegisteredAndRunningLocked", in: registration)
        let install = try XCTUnwrap(ensure.range(of: "installLaunchAgent()"))
        let kickstart = try XCTUnwrap(ensure.range(of: "[\"kickstart\", \"-k\", serviceTarget]"))
        let readiness = try XCTUnwrap(ensure.range(of: "waitForReadiness()"))
        let verification = try XCTUnwrap(ensure.range(
            of: "requireSuccess([\"print\", serviceTarget])"
        ))

        XCTAssertLessThan(install.lowerBound, kickstart.lowerBound)
        XCTAssertLessThan(kickstart.lowerBound, readiness.lowerBound)
        XCTAssertLessThan(readiness.lowerBound, verification.lowerBound)
        XCTAssertFalse(registration.contains("restartRegisteredAgent"))
        XCTAssertFalse(registration.contains("NSWorkspace"))
        XCTAssertFalse(registration.contains("launchApplication"))
    }

    func testUnavailableAgentUsesGroupedRequestAndDoesNotOwnRestart() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let unavailable = try classBody(named: "UnavailableControlAgent", in: delegate)

        XCTAssertTrue(delegate.contains(
            "class UnavailableControlAgent: AgentControlling, @unchecked Sendable"
        ))
        XCTAssertTrue(unavailable.contains(
            "requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus"
        ))
        XCTAssertFalse(unavailable.contains("func restart"))
    }

    func testStartAtLoginMutationUsesSerialBackgroundBoundaryAndPublishesOnMainActor() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let change = try functionBody(named: "startAtLoginChanged", in: controller)
        let capture = try XCTUnwrap(change.range(
            of: "let enabled = startAtLoginSwitch.state == .on"
        ))
        let revision = try XCTUnwrap(change.range(of: "startAtLoginRevision &+= 1"))
        let revisionCapture = try XCTUnwrap(change.range(
            of: "let revision = startAtLoginRevision"
        ))
        let mutation = try XCTUnwrap(change.range(
            of: "registrationController.setStartAtLoginEnabled(enabled) {"
        ))
        let staleGuard = try XCTUnwrap(change.range(
            of: "guard revision == self.startAtLoginRevision else { return }"
        ))
        let publication = try XCTUnwrap(change.range(of: "localErrorKey ="))
        let background = try bracedBody(
            after: "public func setStartAtLoginEnabled(\n        _ enabled: Bool,",
            in: registration
        )
        let queue = try XCTUnwrap(background.range(of: "preferenceQueue.async"))
        let synchronousMutation = try XCTUnwrap(background.range(
            of: "try setStartAtLoginEnabled(enabled)"
        ))

        XCTAssertLessThan(capture.lowerBound, mutation.lowerBound)
        XCTAssertLessThan(revision.lowerBound, revisionCapture.lowerBound)
        XCTAssertLessThan(revisionCapture.lowerBound, mutation.lowerBound)
        XCTAssertLessThan(mutation.lowerBound, publication.lowerBound)
        XCTAssertLessThan(staleGuard.lowerBound, publication.lowerBound)
        XCTAssertFalse(change.contains("Task.detached"))
        XCTAssertTrue(change.contains("Task { @MainActor"))
        XCTAssertLessThan(queue.lowerBound, synchronousMutation.lowerBound)
        XCTAssertFalse(background.contains("localErrorKey"))
        XCTAssertFalse(background.contains("render()"))
    }

    func testLaunchAgentAndTrackedPlistsKeepStableIdentity() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let appPlist = try plist("Configuration/VeloopApp-Info.plist")

        XCTAssertTrue(registration.contains("/Applications/Veloop.app"))
        XCTAssertTrue(registration.contains("appendingPathComponent(\"Contents/MacOS/Veloop\")"))
        XCTAssertTrue(registration.contains("[agentExecutableURL.path, \"--agent\"]"))
        XCTAssertFalse(registration.contains("Contents/Library/LoginItems"))
        XCTAssertFalse(registration.contains("Veloop Agent.app"))
        XCTAssertFalse(registration.contains("ensurePersistentAgentInstalled"))
        XCTAssertEqual(appPlist["CFBundleIdentifier"] as? String, "com.veloop.app")
        XCTAssertEqual(appPlist["CFBundleExecutable"] as? String, "Veloop")
        XCTAssertEqual(appPlist["CFBundleDisplayName"] as? String, "Veloop")
        XCTAssertFalse(exists("Configuration/VeloopAgent-Info.plist"))
        XCTAssertFalse(exists("Sources/App/AgentRegistrationController.swift"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    private func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func functionBody(named name: String, in source: String) throws -> Substring {
        try bracedBody(after: "func \(name)", in: source)
    }

    private func functionOrPropertyBody(named name: String, in source: String) throws -> Substring {
        try bracedBody(after: name, in: source)
    }

    private func classBody(named name: String, in source: String) throws -> Substring {
        try bracedBody(after: "class \(name)", in: source)
    }

    private func bracedBody(after marker: String, in source: String) throws -> Substring {
        let markerRange = try XCTUnwrap(source.range(of: marker), "Missing \(marker)")
        let open = try XCTUnwrap(
            source[markerRange.upperBound...].firstIndex(of: "{"),
            "Missing opening brace after \(marker)"
        )
        var depth = 0
        var index = open
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[open...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }
        XCTFail("Missing closing brace after \(marker)")
        return source[open...]
    }
}
