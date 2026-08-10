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

    func testModelRestartsCurrentAgentBeforeLaunchSynchronizationAndHasNoNoopBridge() throws {
        let model = try text("Sources/Core/Control/ControlViewModel.swift")
        let synchronization = try functionBody(named: "synchronizeOnLaunch", in: model)
        let restart = try XCTUnwrap(
            synchronization.range(of: "lifecycle.restartRegisteredAgent()")
        )
        let reload = try XCTUnwrap(synchronization.range(of: "reloadWithRetry"))

        XCTAssertLessThan(restart.lowerBound, reload.lowerBound)
        XCTAssertFalse(synchronization.contains("lifecycle.ensureRegisteredAndRunning()"))
        XCTAssertFalse(model.contains("permissionRefreshPending"))
        XCTAssertFalse(model.contains("markPermissionRefreshPending"))
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
            "restartRegisteredAgent",
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

    func testEnsureKickstartsWithoutKThenVerifiesLoaded() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let ensure = try functionBody(named: "ensureRegisteredAndRunningLocked", in: registration)
        let install = try XCTUnwrap(ensure.range(of: "installLaunchAgent()"))
        let kickstart = try XCTUnwrap(ensure.range(
            of: "requireSuccess([\"kickstart\", serviceTarget])"
        ))
        let verification = try XCTUnwrap(ensure.range(
            of: "requireSuccess([\"print\", serviceTarget])"
        ))

        XCTAssertLessThan(install.lowerBound, kickstart.lowerBound)
        XCTAssertLessThan(kickstart.lowerBound, verification.lowerBound)
    }

    func testRestartEnsuresRegistrationThenUsesExactLaunchctlKickstart() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let restart = try functionBody(named: "restartRegisteredAgent", in: registration)
        let ensure = try XCTUnwrap(restart.range(of: "ensureRegisteredAndRunningLocked()"))
        let kickstart = try XCTUnwrap(restart.range(
            of: "requireSuccess([\"kickstart\", \"-k\", serviceTarget])"
        ))

        XCTAssertLessThan(ensure.lowerBound, kickstart.lowerBound)
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
        let agentPlist = try plist("Configuration/VeloopAgent-Info.plist")

        XCTAssertTrue(registration.contains("label = \"com.veloop.service\""))
        XCTAssertTrue(registration.contains("Contents/Library/LoginItems"))
        XCTAssertTrue(registration.contains("appendingPathComponent(\"Veloop.app\")"))
        XCTAssertTrue(registration.contains("/Applications/Veloop Agent.app"))
        XCTAssertTrue(registration.contains("Applications/Veloop Agent.app"))
        XCTAssertTrue(registration.contains("ensurePersistentAgentInstalled()"))
        XCTAssertTrue(registration.contains(
            "fileManager.fileExists(atPath: installedAgentBundleURL.path)"
        ))
        XCTAssertFalse(registration.contains("appendingPathComponent(\"VeloopService.app\")"))
        XCTAssertTrue(registration.contains("appendingPathComponent(\"Contents/MacOS/Veloop\")"))
        XCTAssertTrue(registration.contains("\"AssociatedBundleIdentifiers\": [\"com.veloop.app\"]"))
        XCTAssertEqual(appPlist["CFBundleIdentifier"] as? String, "com.veloop.app")
        XCTAssertEqual(appPlist["CFBundleExecutable"] as? String, "Veloop")
        XCTAssertEqual(appPlist["CFBundleDisplayName"] as? String, "Veloop")
        XCTAssertEqual(agentPlist["CFBundleIdentifier"] as? String, "com.veloop.service")
        XCTAssertEqual(agentPlist["CFBundleExecutable"] as? String, "Veloop")
        XCTAssertEqual(agentPlist["CFBundleDisplayName"] as? String, "Veloop")
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
