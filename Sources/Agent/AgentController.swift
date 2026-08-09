import Foundation
import VeloopCore

final class AgentController {
    private let runtime: VeloopAgentRuntime

    init() throws {
        self.runtime = try VeloopAgentRuntime()
    }

    func start() throws {
        try runtime.start()
    }

    func stop() {
        runtime.stop()
    }
}
