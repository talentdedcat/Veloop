import Foundation

final class PermissionRecoveryMonitor {
    static let intervalMilliseconds = 100

    private let readStatus: () -> EventPermissionStatus
    private let onRecovered: (EventPermissionStatus) -> Void
    private var timer: DispatchSourceTimer?

    init(
        readStatus: @escaping () -> EventPermissionStatus,
        onRecovered: @escaping (EventPermissionStatus) -> Void
    ) {
        self.readStatus = readStatus
        self.onRecovered = onRecovered
    }

    func start() {
        precondition(Thread.isMainThread)
        guard timer == nil else { return }
        guard !checkNow() else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.intervalMilliseconds),
            repeating: .milliseconds(Self.intervalMilliseconds),
            leeway: .milliseconds(20)
        )
        timer.setEventHandler { [weak self] in
            _ = self?.checkNow()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        precondition(Thread.isMainThread)
        timer?.cancel()
        timer = nil
    }

    @discardableResult
    func checkNow() -> Bool {
        precondition(Thread.isMainThread)
        let status = readStatus()
        guard status.canCycle else { return false }
        stop()
        onRecovered(status)
        return true
    }

    deinit {
        timer?.cancel()
    }
}
