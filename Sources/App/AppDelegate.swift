import AppKit
import OSLog
import VeloopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let paletteLogger = Logger(
        subsystem: "com.veloop.app",
        category: "palette-install"
    )
    private static let migrationLogger = Logger(
        subsystem: "com.veloop.app",
        category: "permission-identity-migration"
    )
    private static let setupLogger = Logger(
        subsystem: "com.veloop.app",
        category: "application-setup"
    )

    private let paletteInputSourceInstaller = PaletteInputSourceInstaller()
    private let agentRegistrationController = AgentRegistrationController()
    private let localizationController = LocalizationController()
    private var controlWindowController: ControlWindowController?
    private var viewModel: ControlViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let cleanupPaths = VeloopCleanupPaths.userDefault()
            let cleanupController = VeloopCleanupController.live(paths: cleanupPaths)
            let migrator = PermissionIdentityMigrator(
                executableURL: URL(
                    fileURLWithPath: "/Applications/Veloop.app/Contents/MacOS/Veloop"
                ),
                receiptURL: cleanupPaths.permissionIdentityReceipt,
                cleanup: {
                    try cleanupController.cleanup(
                        scope: .preserveUserData,
                        includeWatcher: false
                    )
                }
            )
            try migrator.migrateIfNeeded()
        } catch {
            let errorType = String(reflecting: type(of: error))
            Self.migrationLogger.error(
                "Permission identity migration failed type=\(errorType, privacy: .public)"
            )
            NSApplication.shared.terminate(nil)
            return
        }

        do {
            let bundledWatcher = Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Resources/VeloopUninstallWatcher"
            )
            try UninstallWatcherInstaller(
                bundledExecutableURL: bundledWatcher,
                launchctl: { arguments in
                    try Self.runLaunchctl(arguments)
                }
            ).install()
        } catch {
            let errorType = String(reflecting: type(of: error))
            Self.setupLogger.error(
                "Uninstall watcher setup failed type=\(errorType, privacy: .public)"
            )
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = localizationController.string("setup.error.title")
            alert.informativeText = localizationController.string("setup.error.message")
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }

        ensurePaletteInstalled()

        let agent: AgentControlling
        do {
            agent = try AgentControlClient()
        } catch {
            agent = UnavailableControlAgent()
        }
        let viewModel = ControlViewModel(
            agent: agent,
            lifecycle: agentRegistrationController
        )
        let controller = ControlWindowController(
            localization: localizationController,
            model: viewModel,
            registrationController: agentRegistrationController
        )
        controller.showWindow(nil)
        self.viewModel = viewModel
        controlWindowController = controller
        Task { await viewModel.synchronizeOnLaunch() }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let viewModel else { return }
        ensurePaletteInstalled()
        Task { await viewModel.applicationDidBecomeActive() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func ensurePaletteInstalled() {
        do {
            try paletteInputSourceInstaller.ensureInstalled()
        } catch {
            let errorType = String(reflecting: type(of: error))
            Self.paletteLogger.error(
                "Palette installation failed type=\(errorType, privacy: .public)"
            )
        }
    }

    nonisolated private static func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

private final class UnavailableControlAgent: AgentControlling, @unchecked Sendable {
    func state() throws -> ControlState { throw UnavailableControlAgentError.unavailable }
    func update(_ update: ControlUpdate) throws -> ControlState { throw UnavailableControlAgentError.unavailable }
    func clearHistory() throws { throw UnavailableControlAgentError.unavailable }
    func requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus {
        throw UnavailableControlAgentError.unavailable
    }
}

private enum UnavailableControlAgentError: Error {
    case unavailable
}
