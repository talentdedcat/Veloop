import AppKit
import Foundation

final class AgentProcessRestarter {
    typealias Schedule = (@escaping () -> Void) -> Void
    typealias Launch = (URL, @escaping (Error?) -> Void) -> Void
    typealias Terminate = (Int32) -> Void

    private let schedule: Schedule
    private let launch: Launch
    private let terminate: Terminate

    init(
        schedule: @escaping Schedule,
        launch: @escaping Launch,
        terminate: @escaping Terminate
    ) {
        self.schedule = schedule
        self.launch = launch
        self.terminate = terminate
    }

    convenience init() {
        self.init(
            schedule: { operation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: operation)
            },
            launch: { bundleURL, completion in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                    completion(error)
                }
            },
            terminate: { exit($0) }
        )
    }

    func restart(bundleURL: URL, stop: @escaping () -> Void) {
        schedule { [launch, terminate] in
            stop()
            launch(bundleURL) { error in
                terminate(error == nil ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
}
