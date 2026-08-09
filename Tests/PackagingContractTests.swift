import Foundation
import XCTest

final class PackagingContractTests: XCTestCase {
    func testCommandLineEntryPointUsesTargetSpecificDirectory() throws {
        let project = try text("Veloop.xcodeproj/project.pbxproj")
        let readme = try text("README.md")
        let chineseReadme = try text("Docs/README.zh-CN.md")
        let sourceGuide = try text("Sources/README.md")

        XCTAssertTrue(exists("Sources/Veloopctl/main.swift"))
        XCTAssertFalse(exists("Sources/CommandLine"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/VeloopCLI.swift"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/AgentClient.swift"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/AgentServer.swift"))
        XCTAssertTrue(project.contains("/* Veloopctl */"))
        XCTAssertTrue(project.contains("path = Veloopctl;"))
        XCTAssertFalse(project.contains("path = CommandLine;"))
        XCTAssertTrue(project.contains("name = veloopctl;"))
        XCTAssertTrue(project.contains("productName = veloopctl;"))
        XCTAssertTrue(project.contains("PRODUCT_NAME = veloopctl;"))
        XCTAssertTrue(readme.contains("Sources/Veloopctl/"))
        XCTAssertTrue(chineseReadme.contains("Sources/Veloopctl/"))
        XCTAssertTrue(sourceGuide.contains("`Veloopctl` is the thin `veloopctl` entry point"))
        XCTAssertFalse(sourceGuide.contains("`CommandLine` is the thin `veloopctl` entry point"))
    }

    func testPublicTreeKeepsReleaseToolingLocal() throws {
        let root = repositoryRoot
        let releaseWorkflow = try text(".github/workflows/release.yml")
        let buildWorkflow = try text(".github/workflows/build.yml")
        let gitignore = try text(".gitignore")

        XCTAssertFalse(exists("Packaging/LaunchAgent/com.veloop.agent.plist"))
        XCTAssertFalse(exists("Packaging/create-release-archive.sh"))
        XCTAssertFalse(exists("Packaging/verify-release.sh"))
        XCTAssertTrue(exists("Packaging/create-release-dmg.sh"))
        XCTAssertTrue(exists("Packaging/verify-dmg.sh"))
        XCTAssertTrue(gitignore.contains("Configuration/"))
        XCTAssertTrue(gitignore.contains("Packaging/"))
        XCTAssertTrue(gitignore.contains("Veloop.xcodeproj/"))
        XCTAssertTrue(gitignore.contains(".github/workflows/"))
        XCTAssertTrue(releaseWorkflow.contains(".dmg"))
        XCTAssertFalse(releaseWorkflow.contains(".zip"))
        XCTAssertTrue(buildWorkflow.contains("create-release-dmg.sh"))
        XCTAssertTrue(buildWorkflow.contains("verify-dmg.sh"))
        XCTAssertTrue(buildWorkflow.contains("Veloop-0.1.0-universal.dmg"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testLocalDMGAdHocUsesCDHashBoundRequirementsInNestedOrder() throws {
        let script = try text("Packaging/create-release-dmg.sh")

        let cli = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$cli\""))
        let palette = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$palette\""))
        let agent = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$agent\""))
        let app = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$staged_app\""))

        XCTAssertLessThan(cli.lowerBound, palette.lowerBound)
        XCTAssertLessThan(palette.lowerBound, agent.lowerBound)
        XCTAssertLessThan(agent.lowerBound, app.lowerBound)
        XCTAssertFalse(script.contains("--requirements"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$staged_app\""))
    }

    func testEmbeddedAgentUsesTheUserFacingVeloopIdentity() throws {
        let plistURL = repositoryRoot.appendingPathComponent("Configuration/VeloopAgent-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let project = try text("Veloop.xcodeproj/project.pbxproj")
        let registration = try text("Sources/App/AgentRegistrationController.swift")
        let constants = try text("Sources/Core/Support/AppConstants.swift")
        let verifier = try text("Packaging/verify-dmg.sh")

        XCTAssertEqual(plist["CFBundleName"] as? String, "Veloop")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Veloop")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "Veloop.icns")
        XCTAssertTrue(exists("Sources/Agent/Veloop.icns"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.veloop.service;"))
        XCTAssertTrue(registration.contains("label = \"com.veloop.service\""))
        XCTAssertTrue(constants.contains("bundleIdentifier = \"com.veloop.service\""))
        XCTAssertTrue(verifier.contains("com.veloop.service"))
        XCTAssertTrue(verifier.contains("Print :CFBundleDisplayName"))
        XCTAssertTrue(verifier.contains("Veloop.icns"))
    }

    func testEmbeddedServiceBundleAndExecutableAreNamedVeloop() throws {
        let project = try text("Veloop.xcodeproj/project.pbxproj")
        let buildScript = try text("Packaging/build-release.sh")
        let dmgScript = try text("Packaging/create-release-dmg.sh")
        let verifier = try text("Packaging/verify-dmg.sh")
        let expectedBundlePath = "Contents/Library/LoginItems/Veloop.app"
        let expectedExecutablePath = "Contents/MacOS/Veloop"

        XCTAssertTrue(project.contains("path = VeloopService.app; sourceTree = BUILT_PRODUCTS_DIR;"))
        XCTAssertTrue(project.contains("PRODUCT_NAME = VeloopService; SKIP_INSTALL = YES"))
        XCTAssertFalse(project.contains("PBXShellScriptBuildPhase"))
        XCTAssertTrue(buildScript.contains("Contents/Library/LoginItems/VeloopService.app/\(expectedExecutablePath)"))
        XCTAssertTrue(dmgScript.contains("source_agent=\"$login_items/VeloopService.app\""))
        XCTAssertTrue(dmgScript.contains("agent=\"$login_items/Veloop.app\""))
        XCTAssertTrue(dmgScript.contains("mv \"$source_agent\" \"$agent\""))
        XCTAssertTrue(verifier.contains("\(expectedBundlePath)"))
        XCTAssertTrue(verifier.contains("\(expectedExecutablePath)"))
        XCTAssertFalse(buildScript.contains("LoginItems/VeloopAgent.app"))
        XCTAssertFalse(dmgScript.contains("LoginItems/VeloopAgent.app"))
        XCTAssertFalse(verifier.contains("LoginItems/VeloopAgent.app"))
    }

    func testStorageStepperUsesTheOneMegabyteContract() throws {
        let controller = try text("Sources/App/ControlViewController.swift")

        XCTAssertTrue(controller.contains(
            "increment: Double(ControlLimitInput.storageStepMegabytes)"
        ))
    }

    func testPublicReleaseUsesTheInitialBuildNumber() throws {
        let project = try text("Veloop.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("MARKETING_VERSION = 0.1.0;"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION = 1;"))
    }

    func testPaletteHelperIsHiddenEmbeddedAndUniversal() throws {
        let project = try text("Veloop.xcodeproj/project.pbxproj")
        let build = try text("Packaging/build-release.sh")
        let verifier = try text("Packaging/verify-dmg.sh")
        let plistURL = repositoryRoot.appendingPathComponent("Configuration/VeloopPalette-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertTrue(project.contains("VeloopPalette.app in Embed Input Methods"))
        XCTAssertTrue(project.contains("Contents/Library/Input Methods"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.talentdedcat.veloop.palette;"))
        XCTAssertTrue(build.contains("Contents/Library/Input Methods/VeloopPalette.app/Contents/MacOS/VeloopPalette"))
        XCTAssertTrue(verifier.contains("Contents/Library/Input Methods/VeloopPalette.app"))
        XCTAssertEqual(plist["InputMethodType"] as? String, "palette")
        XCTAssertEqual(plist["TISInputSourceID"] as? String, "com.talentdedcat.veloop.palette")
        XCTAssertEqual(plist["ComponentInvisibleInSystemUI"] as? Bool, true)
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testAppInstallsPaletteBeforeStartingAgent() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let main = try text("Sources/App/main.swift")
        XCTAssertTrue(delegate.contains("@MainActor\nfinal class AppDelegate"))
        XCTAssertTrue(main.contains("MainActor.assumeIsolated"))
        let launch = try XCTUnwrap(delegate.range(of: "func applicationDidFinishLaunching"))
        let palette = try XCTUnwrap(
            delegate.range(of: "ensurePaletteInstalled()", range: launch.lowerBound..<delegate.endIndex)
        )
        let agent = try XCTUnwrap(delegate.range(of: "agentRegistrationController.ensureRegistered()"))

        XCTAssertLessThan(palette.lowerBound, agent.lowerBound)
    }

    func testPaletteInstallerRegistersButNeverSelects() throws {
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")

        XCTAssertTrue(installer.contains("Library/Input Methods"))
        XCTAssertTrue(installer.contains("copyItem"))
        XCTAssertTrue(installer.contains("TISRegisterInputSource"))
        XCTAssertTrue(installer.contains("Contents/Info.plist"))
        XCTAssertTrue(installer.contains("palette-host-path"))
        XCTAssertTrue(installer.contains("@MainActor"))
        XCTAssertFalse(installer.contains("PaletteInputSourceActivator"))
        XCTAssertFalse(installer.contains("TISSelectInputSource"))
        XCTAssertFalse(installer.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertFalse(installer.contains("NSLock"))
        XCTAssertFalse(installer.contains("createSymbolicLink"))
    }

    func testPaletteActivationIsOwnedByInputSubsystemCoordinator() throws {
        let activator = try text("Sources/Core/Support/PaletteInputSourceActivator.swift")
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertTrue(activator.contains("TISEnableInputSource"))
        XCTAssertTrue(activator.contains("TISSelectInputSource"))
        XCTAssertTrue(activator.contains("TISDeselectInputSource"))
        XCTAssertFalse(activator.contains("TISDisableInputSource"))
        XCTAssertTrue(activator.contains("activateDuringStartup()"))
        XCTAssertTrue(activator.contains("Task.sleep"))
        XCTAssertFalse(installer.contains("PaletteInputSourceActivator"))
        XCTAssertTrue(runtime.contains("InputSubsystemCoordinator("))
        XCTAssertTrue(runtime.contains("synchronizeInputSubsystem()"))
        XCTAssertTrue(runtime.contains("inputSubsystem.stop()"))
        XCTAssertFalse(runtime.contains("paletteActivationTask"))
        XCTAssertFalse(runtime.contains("DispatchQueue.main.asyncAfter"))
    }

    func testPaletteInstallationFailuresAreLoggedWithoutSensitiveDetails() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")

        XCTAssertTrue(delegate.contains("palette-install"))
        XCTAssertTrue(delegate.contains("String(reflecting: type(of: error))"))
        XCTAssertFalse(delegate.contains("try? paletteInputSourceInstaller.ensureInstalled()"))
        XCTAssertFalse(delegate.contains("error.localizedDescription"))
    }

    func testDoctorReportsPaletteInstallationEnabledAndSelectionState() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")
        let activator = try text("Sources/Core/Support/PaletteInputSourceActivator.swift")

        XCTAssertTrue(runtime.contains("paletteInstalled="))
        XCTAssertTrue(runtime.contains("paletteEnabled="))
        XCTAssertTrue(runtime.contains("paletteSelected="))
        XCTAssertTrue(activator.contains("kTISPropertyInputSourceIsEnabled"))
        XCTAssertTrue(activator.contains("kTISPropertyInputSourceIsSelected"))
    }

    func testReturningFromPermissionSettingsRefreshesTheHelperOwnedState() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let delegate = try text("Sources/App/AppDelegate.swift")
        let mark = try XCTUnwrap(controller.range(of: "model.markPermissionRefreshPending()"))
        let open = try XCTUnwrap(controller.range(of: "NSWorkspace.shared.open(url)"))

        XCTAssertLessThan(mark.lowerBound, open.lowerBound)
        XCTAssertTrue(delegate.contains("await viewModel.applicationDidBecomeActive()"))
        XCTAssertFalse(delegate.contains("await viewModel.reload()"))
    }

    func testApplicationLaunchSynchronizesHelperOwnedPermissionState() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")

        let registration = try XCTUnwrap(delegate.range(of: "try? agentRegistrationController.ensureRegistered()"))
        let showWindow = try XCTUnwrap(delegate.range(of: "controller.showWindow(nil)"))
        let synchronize = try XCTUnwrap(delegate.range(of: "await viewModel.synchronizeOnLaunch()"))
        XCTAssertLessThan(registration.lowerBound, showWindow.lowerBound)
        XCTAssertLessThan(showWindow.lowerBound, synchronize.lowerBound)
        XCTAssertFalse(delegate.contains("launchAgent()"))
        XCTAssertFalse(delegate.contains("startupTask"))
    }

    func testApplicationActivationEnsuresAgentBeforeRefreshingState() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let activation = try XCTUnwrap(delegate.range(of: "func applicationDidBecomeActive"))
        let suffix = delegate[activation.lowerBound...]
        let launch = try XCTUnwrap(suffix.range(of: "try? agentRegistrationController.ensureRegistered()"))
        let refresh = try XCTUnwrap(suffix.range(of: "await viewModel.applicationDidBecomeActive()"))

        XCTAssertLessThan(launch.lowerBound, refresh.lowerBound)
    }

    func testAgentLaunchDoesNotRequestPermissions() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertFalse(runtime.contains("permissions.requestOnceIfNeeded()"))
    }

    func testLoginStartupUsesAUserLaunchAgentAndOnlyMigratesLegacyServiceManagement() throws {
        let registration = try text("Sources/App/AgentRegistrationController.swift")

        XCTAssertTrue(registration.contains("Library/LaunchAgents"))
        XCTAssertTrue(registration.contains("launchctl"))
        XCTAssertTrue(registration.contains("unregisterLegacyService"))
        XCTAssertFalse(registration.contains("service.register()"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
