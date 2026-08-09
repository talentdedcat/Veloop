import Foundation

public enum ControlViewModelError: Equatable, Sendable {
    case agentUnavailable
    case updateFailed
    case clearFailed
    case permissionRequestFailed
    case restartFailed
}

public struct AgentRetryPolicy: Equatable, Sendable {
    public static let production = AgentRetryPolicy()

    public let maximumAttempts: Int
    public let delayNanoseconds: UInt64

    public init(
        maximumAttempts: Int = 30,
        delayNanoseconds: UInt64 = 100_000_000
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.delayNanoseconds = delayNanoseconds
    }
}

public enum PermissionSyncState: Equatable, Sendable {
    case checking
    case available(EventPermissionStatus)
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
    private let retryPolicy: AgentRetryPolicy
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let queue = DispatchQueue(label: "com.veloop.control", qos: .utility)
    private var permissionRefreshPending = false
    private var launchSynchronizationInProgress = false
    private var synchronizationRevision: UInt64 = 0

    public init(
        agent: AgentControlling,
        lifecycle: AgentLifecycleControlling,
        retryPolicy: AgentRetryPolicy = .production,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.agent = agent
        self.lifecycle = lifecycle
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    // Temporary compatibility initializer for the app target; Task 4 injects its lifecycle controller.
    public convenience init(agent: AgentControlling) {
        self.init(agent: agent, lifecycle: CompatibilityAgentLifecycle())
    }

    public func markPermissionRefreshPending() {
        permissionRefreshPending = true
    }

    public func applicationDidBecomeActive() async {
        guard !Task.isCancelled else { return }
        guard permissionRefreshPending else {
            guard !launchSynchronizationInProgress else { return }
            await reload()
            return
        }

        permissionRefreshPending = false
        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let restartResult: Result<Void, Error> = await offMain { [lifecycle] in
            try lifecycle.restartRegisteredAgent()
        }
        guard !shouldStop(revision: revision) else { return }
        guard case .success = restartResult else {
            publishFailure(.restartFailed, revision: revision)
            return
        }

        await reloadWithRetry(revision: revision)
    }

    public func synchronizeOnLaunch() async {
        guard !Task.isCancelled else { return }
        guard !launchSynchronizationInProgress else { return }
        launchSynchronizationInProgress = true
        defer { launchSynchronizationInProgress = false }

        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let registrationResult: Result<Void, Error> = await offMain { [lifecycle] in
            try lifecycle.ensureRegisteredAndRunning()
        }
        guard !shouldStop(revision: revision) else { return }
        guard case .success = registrationResult else {
            publishFailure(.agentUnavailable, revision: revision)
            return
        }

        await reloadWithRetry(revision: revision)
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

    public func requestPermissions(_ group: EventPermissionGroup) async {
        guard !Task.isCancelled else { return }
        guard case let .available(permissions) = permissionSyncState,
              !permissions.isAllowed(for: group) else {
            return
        }

        let revision = beginSynchronization()
        guard !shouldStop(revision: revision) else { return }
        let requestResult = await offMain { [agent] in
            try agent.requestPermissions(group)
        }
        guard !shouldStop(revision: revision) else { return }
        guard case .success = requestResult else {
            publishFailure(.permissionRequestFailed, revision: revision)
            return
        }

        guard !shouldStop(revision: revision) else { return }
        let stateResult = await offMain { [agent] in try agent.state() }
        guard !shouldStop(revision: revision) else { return }
        switch stateResult {
        case let .success(state):
            publishFresh(state, revision: revision)
        case .failure:
            publishFailure(.permissionRequestFailed, revision: revision)
        }
    }

    private func reloadWithRetry(revision: UInt64) async {
        for attempt in 0..<retryPolicy.maximumAttempts {
            guard !shouldStop(revision: revision) else { return }
            let result = await offMain { [agent] in try agent.state() }
            guard !shouldStop(revision: revision) else { return }
            if case let .success(state) = result {
                publishFresh(state, revision: revision)
                return
            }
            if attempt + 1 < retryPolicy.maximumAttempts {
                do {
                    try await sleep(retryPolicy.delayNanoseconds)
                } catch {
                    stopLoadingIfCurrent(revision: revision)
                    return
                }
                guard !shouldStop(revision: revision) else { return }
            }
        }
        publishFailure(.agentUnavailable, revision: revision)
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

private final class CompatibilityAgentLifecycle: AgentLifecycleControlling {
    func ensureRegisteredAndRunning() throws {}
    func restartRegisteredAgent() throws {}
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
