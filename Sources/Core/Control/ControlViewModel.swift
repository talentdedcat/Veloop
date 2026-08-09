import Foundation

public enum ControlViewModelError: Equatable, Sendable {
    case agentUnavailable
    case updateFailed
    case clearFailed
    case permissionRequestFailed
    case restartFailed
}

@MainActor
public final class ControlViewModel {
    private static let stateAttempts = 30
    private static let stateDelayNanoseconds: UInt64 = 100_000_000

    public private(set) var state: ControlState?
    public private(set) var inlineError: ControlViewModelError?
    public private(set) var isLoading = false
    public var onChange: (() -> Void)?

    private let agent: AgentControlling
    private let queue = DispatchQueue(label: "com.veloop.control", qos: .utility)
    private var permissionRefreshPending = false
    private var updateRevision: UInt64 = 0

    public init(agent: AgentControlling) {
        self.agent = agent
    }

    public func markPermissionRefreshPending() {
        permissionRefreshPending = true
    }

    public func applicationDidBecomeActive() async {
        guard permissionRefreshPending else {
            await reload()
            return
        }
        permissionRefreshPending = false
        await restartAndReload()
    }

    public func synchronizeOnLaunch() async {
        beginOperation()
        await reloadWithRetry()
    }

    public func reload() async {
        beginOperation()
        let result = await offMain { [agent] in try agent.state() }
        finish(result, failure: .agentUnavailable)
    }

    public func update(_ update: ControlUpdate) async {
        updateRevision &+= 1
        let revision = updateRevision
        inlineError = nil
        if let state {
            self.state = state.applying(update)
        }
        onChange?()

        let result = await offMain { [agent] in try agent.update(update) }
        guard revision == updateRevision else { return }
        switch result {
        case let .success(state):
            self.state = state
            inlineError = nil
        case .failure:
            let synchronized = await offMain { [agent] in try agent.state() }
            guard revision == updateRevision else { return }
            if case let .success(state) = synchronized {
                self.state = state
            }
            inlineError = .updateFailed
        }
        onChange?()
    }

    public func clearHistory() async {
        beginOperation()
        let result: Result<ControlState, Error> = await offMain { [agent] in
            try agent.clearHistory()
            return try agent.state()
        }
        finish(result, failure: .clearFailed)
    }

    public func requestPermissions(_ group: EventPermissionGroup) async {
        beginOperation()
        let result: Result<ControlState, Error> = await offMain { [agent] in
            _ = try agent.requestPermissions(group)
            return try agent.state()
        }
        finish(result, failure: .permissionRequestFailed)
    }

    private func restartAndReload() async {
        beginOperation()
        let restartResult: Result<Void, Error> = await offMain { [agent] in
            try agent.restart()
        }
        guard case .success = restartResult else {
            fail(.restartFailed)
            return
        }

        await reloadWithRetry()
    }

    private func reloadWithRetry() async {
        for attempt in 0..<Self.stateAttempts {
            let result = await offMain { [agent] in try agent.state() }
            if case .success = result {
                finish(result, failure: .agentUnavailable)
                return
            }
            if attempt + 1 < Self.stateAttempts {
                try? await Task.sleep(nanoseconds: Self.stateDelayNanoseconds)
            }
        }
        fail(.agentUnavailable)
    }

    private func beginOperation() {
        isLoading = true
        inlineError = nil
        onChange?()
    }

    private func finish(_ result: Result<ControlState, Error>, failure: ControlViewModelError) {
        isLoading = false
        switch result {
        case let .success(state):
            self.state = state
            inlineError = nil
        case .failure:
            inlineError = failure
        }
        onChange?()
    }

    private func fail(_ error: ControlViewModelError) {
        isLoading = false
        inlineError = error
        onChange?()
    }

    private func offMain<T>(_ work: @escaping () throws -> T) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { try work() })
            }
        }
    }
}

private extension ControlState {
    func applying(_ update: ControlUpdate) -> ControlState {
        var configuration = configuration
        if let value = update.showContentPreviews {
            configuration.showContentPreviews = value
        }
        if let value = update.maximumHistoryCount {
            configuration.maximumHistoryCount = value
        }
        if let value = update.maximumDiskBytes {
            configuration.maximumDiskBytes = value
        }
        return ControlState(
            enabled: update.enabled ?? enabled,
            historyCount: historyCount,
            storageBytes: storageBytes,
            configuration: configuration,
            permissions: permissions
        )
    }
}
