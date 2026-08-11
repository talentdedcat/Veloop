import Foundation
import XCTest

final class PackagingContractTests: XCTestCase {
    func testLocalSwiftPackageDefinesEveryReleaseExecutableAndPackagingTests() throws {
        let package = try text("Package.swift")
        let sourceGuide = try text("Sources/README.md")

        XCTAssertTrue(package.contains(".executable(name: \"Veloop\", targets: [\"App\"])"))
        XCTAssertTrue(package.contains(".executable(name: \"VeloopUninstallWatcher\", targets: [\"UninstallWatcher\"])"))
        XCTAssertTrue(package.contains(".executable(name: \"veloopctl\", targets: [\"Veloopctl\"])"))
        XCTAssertTrue(package.contains("name: \"App\""))
        XCTAssertTrue(package.contains("path: \"Sources/App\""))
        XCTAssertTrue(package.contains("\"Veloop.icns\""))
        XCTAssertTrue(package.contains("name: \"UninstallWatcher\""))
        XCTAssertTrue(package.contains("path: \"Sources/UninstallWatcher\""))
        XCTAssertFalse(package.contains("name: \"Agent\""))
        XCTAssertFalse(package.contains("path: \"Sources/Agent\""))
        XCTAssertTrue(package.contains("name: \"Veloopctl\""))
        XCTAssertTrue(package.contains("path: \"Sources/Veloopctl\""))
        XCTAssertFalse(package.contains("exclude: [\"PackagingContractTests.swift\"]"))
        XCTAssertTrue(exists("Sources/Veloopctl/main.swift"))
        XCTAssertFalse(exists("Sources/CommandLine"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/VeloopCLI.swift"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/AgentClient.swift"))
        XCTAssertTrue(exists("Sources/Core/CommandLine/AgentServer.swift"))
        XCTAssertTrue(sourceGuide.contains("`Veloopctl` is the thin `veloopctl` entry point"))
        XCTAssertFalse(sourceGuide.contains("`CommandLine` is the thin `veloopctl` entry point"))
    }

    func testPublicTreeKeepsReleaseToolingLocal() throws {
        let gitignore = try text(".gitignore")
        let gitignoreRules = Set(
            gitignore.split(whereSeparator: { $0.isNewline }).map(String.init)
        )

        XCTAssertTrue(exists("Package.swift"))
        XCTAssertTrue(exists("Packaging/build-release.sh"))
        XCTAssertTrue(exists("Packaging/create-release-dmg.sh"))
        XCTAssertTrue(exists("Packaging/verify-dmg.sh"))
        XCTAssertFalse(exists("Packaging/LaunchAgent/com.veloop.agent.plist"))
        XCTAssertFalse(exists("Packaging/create-release-archive.sh"))
        XCTAssertFalse(exists("Packaging/verify-release.sh"))
        XCTAssertTrue(gitignoreRules.contains("Package.swift"))
        XCTAssertFalse(gitignoreRules.contains("Packaging/"))
        XCTAssertTrue(gitignoreRules.contains("Veloop-*-universal.dmg"))
        XCTAssertFalse(gitignoreRules.contains("Configuration/"))
        XCTAssertTrue(exists("Sources/Core/Configuration/Configuration.swift"))
        XCTAssertTrue(exists("Sources/Core/Configuration/ConfigurationStore.swift"))
        XCTAssertFalse(exists("Configuration/VeloopAgent-Info.plist"))
        XCTAssertTrue(exists("Configuration/VeloopApp-Info.plist"))
        XCTAssertTrue(exists("Configuration/VeloopPalette-Info.plist"))
    }

    func testLocalReleaseBuildSignsNestedCodeInRequiredOrder() throws {
        let script = try text("Packaging/build-release.sh")

        let cli = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$cli\""))
        let watcher = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$watcher\""))
        let palette = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$palette\""))
        let app = try XCTUnwrap(script.range(of: "codesign --force --options runtime --sign - \"$staged_app\""))

        XCTAssertLessThan(cli.lowerBound, watcher.lowerBound)
        XCTAssertLessThan(watcher.lowerBound, palette.lowerBound)
        XCTAssertLessThan(palette.lowerBound, app.lowerBound)
        XCTAssertFalse(script.contains("VeloopAgent"))
        XCTAssertFalse(script.contains("LoginItems"))
        XCTAssertFalse(script.contains("--requirements"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$staged_app\""))
    }

    func testDMGVerifierIsReadOnlyAndChecksTheCompleteReleaseContract() throws {
        let verifier = try text("Packaging/verify-dmg.sh")

        XCTAssertTrue(verifier.contains("hdiutil attach -readonly -nobrowse"))
        XCTAssertTrue(verifier.contains("Contents/Resources/VeloopUninstallWatcher"))
        XCTAssertTrue(verifier.contains("Contents/Library/Input Methods/VeloopPalette.app"))
        XCTAssertTrue(verifier.contains("Contents/Resources/veloopctl"))
        XCTAssertTrue(verifier.contains("com.veloop.app"))
        XCTAssertTrue(verifier.contains("com.talentdedcat.veloop.palette"))
        XCTAssertTrue(verifier.contains("CFBundleShortVersionString") && verifier.contains("0.2.0"))
        XCTAssertTrue(verifier.contains("CFBundleVersion") && verifier.contains("\"5\""))
        XCTAssertTrue(verifier.contains("x86_64") && verifier.contains("arm64"))
        XCTAssertTrue(verifier.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(verifier.contains("Veloop Agent.app"))
        XCTAssertTrue(verifier.contains("LoginItems"))
    }

    func testDMGVerifierNeverExecutesMountedCodeOrMutatesUserState() throws {
        let verifier = try text("Packaging/verify-dmg.sh")
        let commandLines = verifier
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for mountedExecutable in [
            "\"$cli\"",
            "\"$watcher\"",
            "\"$staged_app/Contents/MacOS/Veloop\"",
            "\"$palette/Contents/MacOS/VeloopPalette\"",
        ] {
            XCTAssertFalse(
                commandLines.contains { $0 == mountedExecutable || $0.hasPrefix("\(mountedExecutable) ") },
                "verifier must not execute mounted code: \(mountedExecutable)"
            )
        }

        for mutationCommand in [
            "open ", "install ", "installer ", "tccutil ", "defaults ", "launchctl ", "osascript ", "xattr ",
        ] {
            XCTAssertFalse(
                commandLines.contains { $0 == mutationCommand.dropLast() || $0.hasPrefix(mutationCommand) },
                "verifier must not run mutation command: \(mutationCommand)"
            )
        }
        XCTAssertFalse(verifier.contains("$HOME"))
        XCTAssertFalse(verifier.contains("${HOME"))
        XCTAssertFalse(verifier.contains("~/"))
    }

    func testCaskNormalUninstallRunsPurgeWithoutPrivilegedDeleteArtifact() throws {
        let cask = try text("Casks/veloop.rb")
        let uninstallStart = try XCTUnwrap(cask.range(of: "  uninstall "))
        let zapStart = try XCTUnwrap(
            cask.range(of: "\n  zap ", range: uninstallStart.lowerBound..<cask.endIndex)
        )
        let uninstall = cask[uninstallStart.lowerBound..<zapStart.lowerBound]
        XCTAssertTrue(uninstall.contains("uninstall\", \"--purge"))
        XCTAssertTrue(uninstall.contains("must_succeed: true"))
        XCTAssertFalse(uninstall.contains("delete:"))
        XCTAssertFalse(cask.contains("\"/Applications/Veloop Agent.app\""))
    }

    func testOnlyMainApplicationOwnsVeloopPermissionIdentity() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")
        let constants = try text("Sources/Core/Support/AppConstants.swift")
        let verifier = try text("Packaging/verify-dmg.sh")

        XCTAssertTrue(constants.contains("bundleIdentifier = \"com.veloop.app\""))
        XCTAssertTrue(registration.contains("Contents/MacOS/Veloop"))
        XCTAssertTrue(registration.contains("AgentRuntime/Veloop.app"))
        XCTAssertTrue(registration.contains("\"--agent\""))
        XCTAssertFalse(registration.contains("Veloop Agent.app"))
        XCTAssertFalse(exists("Sources/Agent"))
        XCTAssertFalse(exists("Configuration/VeloopAgent-Info.plist"))
        XCTAssertTrue(verifier.contains("bundle_count"))
        XCTAssertTrue(verifier.contains("com.veloop.app"))
    }

    func testPlainWatcherIsEmbeddedWithoutAnApplicationBundle() throws {
        let buildScript = try text("Packaging/build-release.sh")
        let verifier = try text("Packaging/verify-dmg.sh")

        XCTAssertTrue(buildScript.contains("Contents/Resources/VeloopUninstallWatcher"))
        XCTAssertTrue(buildScript.contains("$bin_dir/VeloopUninstallWatcher"))
        XCTAssertTrue(verifier.contains("Contents/Resources/VeloopUninstallWatcher"))
        XCTAssertFalse(buildScript.contains("Contents/Library/LoginItems"))
        XCTAssertFalse(buildScript.contains("VeloopAgent"))
    }

    func testStorageStepperUsesTheOneMegabyteContract() throws {
        let controller = try text("Sources/App/ControlViewController.swift")

        XCTAssertTrue(controller.contains(
            "increment: Double(ControlLimitInput.storageStepMegabytes)"
        ))
    }

    func testPublicReleaseUsesVersion020AndBuildFive() throws {
        for path in [
            "Configuration/VeloopApp-Info.plist",
            "Configuration/VeloopPalette-Info.plist",
        ] {
            let plistURL = repositoryRoot.appendingPathComponent(path)
            let data = try Data(contentsOf: plistURL)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.2.0")
            XCTAssertEqual(plist["CFBundleVersion"] as? String, "5")
        }
    }

    func testPaletteHelperIsHiddenEmbeddedAndUniversal() throws {
        let build = try text("Packaging/build-release.sh")
        let verifier = try text("Packaging/verify-dmg.sh")
        let plistURL = repositoryRoot.appendingPathComponent("Configuration/VeloopPalette-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertTrue(build.contains("Contents/Library/Input Methods/VeloopPalette.app/Contents/MacOS/VeloopPalette"))
        XCTAssertTrue(build.contains("-framework InputMethodKit"))
        XCTAssertTrue(verifier.contains("Contents/Library/Input Methods/VeloopPalette.app"))
        XCTAssertEqual(plist["InputMethodType"] as? String, "palette")
        XCTAssertEqual(plist["TISInputSourceID"] as? String, "com.talentdedcat.veloop.palette")
        XCTAssertEqual(plist["ComponentInvisibleInSystemUI"] as? Bool, true)
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testAppInstallsPaletteBeforeSynchronizingAgent() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let main = try text("Sources/App/main.swift")
        XCTAssertTrue(delegate.contains("@MainActor\nfinal class AppDelegate"))
        XCTAssertTrue(main.contains("MainActor.assumeIsolated"))
        let launch = try XCTUnwrap(delegate.range(of: "func applicationDidFinishLaunching"))
        let palette = try XCTUnwrap(
            delegate.range(of: "ensurePaletteInstalled()", range: launch.lowerBound..<delegate.endIndex)
        )
        let agent = try XCTUnwrap(delegate.range(of: "let agent = AgentControlClient"))

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

    func testPaletteReplacementDisablesSourceBeforeStoppingHelper() throws {
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")
        let replacementStart = try XCTUnwrap(installer.range(of: "if helperNeedsReplacement("))
        let replacementEnd = try XCTUnwrap(installer.range(
            of: "\n        }\n\n        let registrationStatus",
            range: replacementStart.lowerBound..<installer.endIndex
        ))
        let replacement = installer[replacementStart.lowerBound..<replacementEnd.upperBound]

        let disable = try XCTUnwrap(replacement.range(of: "disableInstalledSource()"))
        let gracePeriod = try XCTUnwrap(replacement.range(
            of: "Thread.sleep(forTimeInterval: Self.inputSourceDisableGracePeriod)"
        ))
        let stop = try XCTUnwrap(replacement.range(of: "stopInstalledHelper()"))
        let remove = try XCTUnwrap(replacement.range(of: "removeItem(at: installedURL)"))
        let copy = try XCTUnwrap(replacement.range(of: "copyItem(at: embeddedURL, to: installedURL)"))
        let register = try XCTUnwrap(installer.range(
            of: "TISRegisterInputSource(installedURL as CFURL)",
            range: replacementEnd.upperBound..<installer.endIndex
        ))

        XCTAssertLessThan(disable.lowerBound, stop.lowerBound)
        XCTAssertLessThan(disable.lowerBound, gracePeriod.lowerBound)
        XCTAssertLessThan(gracePeriod.lowerBound, stop.lowerBound)
        XCTAssertLessThan(stop.lowerBound, remove.lowerBound)
        XCTAssertLessThan(remove.lowerBound, copy.lowerBound)
        XCTAssertLessThan(replacementEnd.upperBound, register.lowerBound)
    }

    func testPaletteReplacementGateCoversInstallUnchangedAndUpgradePaths() throws {
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")
        let comparisonStart = try XCTUnwrap(installer.range(
            of: "private func helperNeedsReplacement"
        ))
        let comparisonEnd = try XCTUnwrap(installer.range(
            of: "\n    private func stopInstalledHelper",
            range: comparisonStart.lowerBound..<installer.endIndex
        ))
        let comparison = installer[comparisonStart.lowerBound..<comparisonEnd.lowerBound]

        XCTAssertTrue(comparison.contains(
            "guard fileManager.fileExists(atPath: installedURL.path) else { return true }"
        ))
        XCTAssertTrue(comparison.contains("embeddedData == installedData else"))
        XCTAssertTrue(comparison.contains("return true"))
        XCTAssertTrue(comparison.contains("return false"))
    }

    func testPaletteHelperTerminationIsBoundedWithSIGTERMAsFallback() throws {
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")
        let stopStart = try XCTUnwrap(installer.range(of: "private func stopInstalledHelper"))
        let stopEnd = try XCTUnwrap(installer.range(
            of: "\n    private func disableInstalledSource",
            range: stopStart.lowerBound..<installer.endIndex
        ))
        let stop = installer[stopStart.lowerBound..<stopEnd.lowerBound]

        let terminate = try XCTUnwrap(stop.range(of: "application.terminate()"))
        let deadline = try XCTUnwrap(stop.range(of: "helperTerminationTimeout"))
        let fallback = try XCTUnwrap(stop.range(of: "if !application.isTerminated"))
        let signal = try XCTUnwrap(stop.range(of: "Darwin.kill(application.processIdentifier, SIGTERM)"))

        XCTAssertLessThan(terminate.lowerBound, deadline.lowerBound)
        XCTAssertLessThan(deadline.lowerBound, fallback.lowerBound)
        XCTAssertLessThan(fallback.lowerBound, signal.lowerBound)
    }

    func testPaletteActivationIsOwnedByInputSubsystemCoordinator() throws {
        let activator = try text("Sources/Core/Support/PaletteInputSourceActivator.swift")
        let installer = try text("Sources/App/PaletteInputSourceInstaller.swift")
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertFalse(activator.contains("TISEnableInputSource"))
        XCTAssertTrue(activator.contains("guard status(for: source).enabled else { return false }"))
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
        XCTAssertTrue(delegate.contains("nsError.domain"))
        XCTAssertTrue(delegate.contains("nsError.code"))
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

    func testEveryApplicationActivationRefreshesTheHelperOwnedState() throws {
        let model = try text("Sources/Core/Control/ControlViewModel.swift")
        let delegate = try text("Sources/App/AppDelegate.swift")

        XCTAssertTrue(model.contains("!permissions.canCycle"))
        XCTAssertTrue(model.contains("restartForPermissionRefresh()"))
        XCTAssertTrue(delegate.contains("await viewModel.applicationDidBecomeActive("))
        XCTAssertTrue(delegate.contains("forcePermissionRefresh: forcePermissionRefresh"))
        XCTAssertFalse(delegate.contains("await viewModel.reload()"))
    }

    func testApplicationLaunchSynchronizesHelperOwnedPermissionState() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")

        let showWindow = try XCTUnwrap(delegate.range(of: "controller.showWindow(nil)"))
        let synchronize = try XCTUnwrap(delegate.range(of: "await viewModel.synchronizeOnLaunch()"))
        XCTAssertLessThan(showWindow.lowerBound, synchronize.lowerBound)
        XCTAssertTrue(delegate.contains("lifecycle: agentRegistrationController"))
        XCTAssertFalse(delegate.contains("ensureRegistered()"))
        XCTAssertFalse(delegate.contains("launchAgent()"))
        XCTAssertFalse(delegate.contains("startupTask"))
    }

    func testApplicationActivationDelegatesAgentRefreshToModel() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let activation = try XCTUnwrap(delegate.range(of: "func applicationDidBecomeActive"))
        let suffix = delegate[activation.lowerBound...]

        XCTAssertTrue(suffix.contains("await viewModel.applicationDidBecomeActive("))
        XCTAssertTrue(suffix.contains("forcePermissionRefresh: forcePermissionRefresh"))
        XCTAssertFalse(suffix.contains("ensureRegistered"))
    }

    func testAgentLaunchDoesNotRequestPermissions() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertFalse(runtime.contains("permissions.requestOnceIfNeeded()"))
    }

    func testLoginStartupUsesAUserLaunchAgentAndOnlyMigratesLegacyServiceManagement() throws {
        let registration = try text("Sources/Core/Agent/AgentRegistrationController.swift")

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
