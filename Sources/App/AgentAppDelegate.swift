import AppKit
import OSLog
import VeloopCore

@MainActor
final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "com.veloop.app",
        category: "agent-start"
    )

    private var runtime: VeloopAgentRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let runtime = try VeloopAgentRuntime()
            try runtime.start()
            self.runtime = runtime
        } catch {
            let errorType = String(reflecting: type(of: error))
            Self.logger.error("Agent start failed type=\(errorType, privacy: .public)")
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }
}
