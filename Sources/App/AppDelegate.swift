import AppKit
import OSLog
import VeloopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let paletteLogger = Logger(
        subsystem: "com.veloop.app",
        category: "palette-install"
    )

    private let paletteInputSourceInstaller = PaletteInputSourceInstaller()
    private let agentRegistrationController = AgentRegistrationController()
    private let localizationController = LocalizationController()
    private var controlWindowController: ControlWindowController?
    private var viewModel: ControlViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensurePaletteInstalled()
        _ = try? agentRegistrationController.ensureRegistered()

        let agent: AgentControlling
        do {
            agent = try AgentControlClient()
        } catch {
            agent = UnavailableControlAgent()
        }
        let viewModel = ControlViewModel(agent: agent)
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
        _ = try? agentRegistrationController.ensureRegistered()
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
}

private final class UnavailableControlAgent: AgentControlling {
    func state() throws -> ControlState { throw UnavailableControlAgentError.unavailable }
    func update(_ update: ControlUpdate) throws -> ControlState { throw UnavailableControlAgentError.unavailable }
    func clearHistory() throws { throw UnavailableControlAgentError.unavailable }
    func requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus {
        throw UnavailableControlAgentError.unavailable
    }
    func restart() throws { throw UnavailableControlAgentError.unavailable }
}

private enum UnavailableControlAgentError: Error {
    case unavailable
}
