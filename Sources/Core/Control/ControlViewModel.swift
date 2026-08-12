import Foundation

public enum ControlViewModelError: Equatable, Sendable {
    case agentUnavailable
    case updateFailed
    case clearFailed
}

public enum PermissionSyncState: Equatable, Sendable {
    case checking
    case available(EventPermissionStatus)
    case unavailable

    public var displayState: PermissionDisplayState {
        switch self {
        case .checking:
            return .checking
        case let .available(status):
            return status.canCycle ? .allowed : .missing
        case .unavailable:
            return .unavailable
        }
    }
}

public enum PermissionDisplayState: Equatable, Sendable {
    case checking
    case allowed
    case missing
    case unavailable
}

@MainActor
public final class ControlViewModel {
    public private(set) var state: ControlState?
    public private(set) var permissionSyncState: PermissionSyncState = .checking
    public private(set) var inlineError: ControlViewModelError?
    public private(set) var isLoading = false
    public var onChange: (() -> Void)?

    private let agent: AgentControlling
    private let lifecycle: AgentLifecycleControlling
    private let queue = DispatchQueue(label: "com.veloop.control", qos: .utility)
    private var launchSynchronizationPrepared = false
    private var launchSynchronizationInProgress = false
    private var suppressNextActivation = false
    private var synchronizationRevision: UInt64 = 0
    private var permissionRefreshInProgress = false

    public init(
        agent: AgentControlling,
        lifecycle: AgentLifecycleControlling
    ) {
        self.agent = agent
        self.lifecycle = lifecycle
    }

    public func applicationDidBecomeActive() async {
        guard !Task.isCancelled else { return }
        if suppressNextActivation {
            suppressNextActivation = false
            return
        }
        guard !launchSynchronizationPrepared else { return }
        guard !launchSynchronizationInProgress else { return }
        await synchronizeAllowingRecovery()
    }

    public func synchronizeOnLaunch() async {
        guard !Task.isCancelled else { return }
        guard !launchSynchronizationInProgress else { return }
        launchSynchronizationPrepared = false
        launchSynchronizationInProgress = true
        defer { launchSynchronizationInProgress = false }

        await synchronizeAllowingRecovery()
    }

    public func prepareForLaunchSynchronization() {
        launchSynchronizationPrepared = true
        suppressNextActivation = true
    }

    public func reload() async {
        guard !Task.isCancelled else { return }
        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let result = await offMain { [agent] in try agent.state() }
        guard !shouldStop(revision: revision) else { return }
        switch result {
        case let .success(state):
            publishFresh(state, revision: revision)
        case .failure:
            publishFailure(.agentUnavailable, revision: revision)
        }
    }

    public func refreshPermissionStatus() async {
        guard !Task.isCancelled, !isLoading, !permissionRefreshInProgress else { return }
        permissionRefreshInProgress = true
        defer { permissionRefreshInProgress = false }
        let revision = synchronizationRevision
        let result = await offMain { [agent] in try agent.state() }
        guard !Task.isCancelled, revision == synchronizationRevision else { return }
        guard case let .success(freshState) = result else { return }
        guard state?.permissions != freshState.permissions else { return }
        state = freshState
        permissionSyncState = .available(freshState.permissions)
        inlineError = nil
        onChange?()
    }

    public func update(_ update: ControlUpdate) async {
        guard !Task.isCancelled else { return }
        let revision = beginOptimisticUpdate(update)
        let result = await offMainCompletingOptimisticUpdate { [agent] in
            try agent.update(update)
        }
        guard isCurrent(revision) else { return }

        switch result {
        case let .success(state):
            publishOptimisticUpdateResult(state, revision: revision)
        case .failure:
            let synchronized = await offMainCompletingOptimisticUpdate { [agent] in
                try agent.state()
            }
            guard isCurrent(revision) else { return }
            switch synchronized {
            case let .success(state):
                publishOptimisticUpdateResult(
                    state,
                    error: .updateFailed,
                    revision: revision
                )
            case .failure:
                publishOptimisticUpdateFailure(revision: revision)
            }
        }
    }

    public func clearHistory() async {
        guard !Task.isCancelled else { return }
        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let clearResult: Result<Void, Error> = await offMain { [agent] in
            try agent.clearHistory()
        }
        guard !shouldStop(revision: revision) else { return }
        guard case .success = clearResult else {
            publishFailure(.clearFailed, revision: revision)
            return
        }

        guard !shouldStop(revision: revision) else { return }
        let stateResult = await offMain { [agent] in try agent.state() }
        guard !shouldStop(revision: revision) else { return }
        switch stateResult {
        case let .success(state):
            publishFresh(state, revision: revision)
        case .failure:
            publishFailure(.clearFailed, revision: revision)
        }
    }

    private func synchronizeAllowingRecovery() async {
        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let fastResult = await offMain { [agent] in try agent.state() }
        guard !shouldStop(revision: revision) else { return }
        if case let .success(state) = fastResult {
            publishFresh(state, revision: revision)
            return
        }

        let recoveryResult: Result<Void, Error> = await offMain { [lifecycle] in
            try lifecycle.ensureRegisteredAndRunning()
        }
        guard !shouldStop(revision: revision) else { return }
        guard case .success = recoveryResult else {
            publishFailure(.agentUnavailable, revision: revision)
            return
        }

        var recoveredState = await offMain { [agent] in try agent.state() }
        if case .failure = recoveredState {
            await waitForAgentToSettle()
            recoveredState = await offMain { [agent] in try agent.state() }
        }
        guard !shouldStop(revision: revision) else { return }
        switch recoveredState {
        case let .success(state):
            publishFresh(state, revision: revision)
        case .failure:
            publishFailure(.agentUnavailable, revision: revision)
        }
    }

    private func beginSynchronization() -> UInt64 {
        synchronizationRevision &+= 1
        state = nil
        permissionSyncState = .checking
        isLoading = true
        inlineError = nil
        onChange?()
        return synchronizationRevision
    }

    private func beginOptimisticUpdate(_ update: ControlUpdate) -> UInt64 {
        synchronizationRevision &+= 1
        inlineError = nil
        if let state {
            self.state = state.applying(update)
        }
        onChange?()
        return synchronizationRevision
    }

    private func publishFresh(
        _ state: ControlState,
        error: ControlViewModelError? = nil,
        revision: UInt64
    ) {
        guard !shouldStop(revision: revision) else { return }
        self.state = state
        permissionSyncState = .available(state.permissions)
        isLoading = false
        inlineError = error
        onChange?()
    }

    private func publishFailure(_ error: ControlViewModelError, revision: UInt64) {
        guard !shouldStop(revision: revision) else { return }
        state = nil
        permissionSyncState = .unavailable
        isLoading = false
        inlineError = error
        onChange?()
    }

    private func publishOptimisticUpdateResult(
        _ state: ControlState,
        error: ControlViewModelError? = nil,
        revision: UInt64
    ) {
        guard isCurrent(revision) else { return }
        self.state = state
        permissionSyncState = .available(state.permissions)
        isLoading = false
        inlineError = error
        onChange?()
    }

    private func publishOptimisticUpdateFailure(revision: UInt64) {
        guard isCurrent(revision) else { return }
        state = nil
        permissionSyncState = .unavailable
        isLoading = false
        inlineError = .updateFailed
        onChange?()
    }

    private func isCurrent(_ revision: UInt64) -> Bool {
        revision == synchronizationRevision
    }

    private func shouldStop(revision: UInt64) -> Bool {
        guard isCurrent(revision) else { return true }
        guard Task.isCancelled else { return false }
        stopLoadingIfCurrent(revision: revision)
        return true
    }

    private func stopLoadingIfCurrent(revision: UInt64) {
        guard isCurrent(revision), isLoading else { return }
        isLoading = false
        onChange?()
    }

    private func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async -> Result<T, Error> {
        let cancellation = OffMainCancellationGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(returning: .failure(CancellationError()))
                        return
                    }
                    continuation.resume(returning: Result { try work() })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func waitForAgentToSettle() async {
        await withCheckedContinuation { continuation in
            queue.asyncAfter(deadline: .now() + .milliseconds(50)) {
                continuation.resume()
            }
        }
    }

    private func offMainCompletingOptimisticUpdate<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async -> Result<T, Error> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { try work() })
            }
        }
    }
}

private final class OffMainCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
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
