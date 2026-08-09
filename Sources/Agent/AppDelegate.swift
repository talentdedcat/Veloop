import AppKit
import VeloopCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AgentController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let controller = try AgentController()
            try controller.start()
            self.controller = controller
        } catch {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
