import Darwin
import Foundation

final class AgentReadinessWaiter: @unchecked Sendable {
    typealias Probe = @Sendable () -> Bool

    private let socketDirectoryURL: URL
    private let timeoutMilliseconds: Int
    private let probe: Probe

    init(
        socketDirectoryURL: URL,
        timeoutMilliseconds: Int = 1_000,
        probe: @escaping Probe
    ) {
        self.socketDirectoryURL = socketDirectoryURL
        self.timeoutMilliseconds = max(1, timeoutMilliseconds)
        self.probe = probe
    }

    func wait() -> Bool {
        if probe() { return true }

        let descriptor = Darwin.open(socketDirectoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let queue = DispatchQueue(label: "com.veloop.agent-readiness")
        let ready = DispatchSemaphore(value: 0)
        let state = ReadinessState()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [probe] in
            guard probe(), state.markReady() else { return }
            ready.signal()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        source.resume()

        let result = ready.wait(
            timeout: .now() + .milliseconds(timeoutMilliseconds)
        ) == .success
        source.cancel()
        return result
    }
}

private final class ReadinessState: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    func markReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !ready else { return false }
        ready = true
        return true
    }
}
