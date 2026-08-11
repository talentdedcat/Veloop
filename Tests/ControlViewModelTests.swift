import Foundation
import XCTest
@testable import VeloopCore

final class ControlViewModelTests: XCTestCase {
    @MainActor
    func testLaunchQueriesStateBeforeAnyRecoveryAndPublishesExactPermissions() async {
        let calls = LockedCalls()
        let permissions = permissionStatus(listen: false, post: true, accessibility: true)
        let agent = ScriptedAgent(calls: calls, states: [.success(controlState(permissions: permissions))])
        let lifecycle = ScriptedLifecycle(calls: calls)
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(calls.values, ["state"])
        XCTAssertEqual(lifecycle.ensureCallCount, 0)
        XCTAssertEqual(model.state?.permissions, permissions)
        XCTAssertEqual(model.permissionSyncState, .available(permissions))
        XCTAssertNil(model.inlineError)
    }

    @MainActor
    func testEveryOrdinaryActivationPublishesFreshStateWithoutRestartingHealthyAgent() async {
        let calls = LockedCalls()
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let first = controlState(enabled: false, permissions: granted)
        let second = controlState(enabled: true, permissions: granted)
        let agent = ScriptedAgent(calls: calls, states: [.success(first), .success(second)])
        let lifecycle = ScriptedLifecycle(calls: calls)
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.applicationDidBecomeActive()
        await model.applicationDidBecomeActive()

        XCTAssertEqual(calls.values, ["state", "state"])
        XCTAssertEqual(lifecycle.ensureCallCount, 0)
        XCTAssertEqual(model.state, second)
    }

    @MainActor
    func testGrantedStateMapsBothPermissionGroupsAllowed() async {
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let agent = ScriptedAgent(states: [.success(controlState(permissions: granted))])
        let model = makeModel(agent: agent)

        await model.reload()

        guard case let .available(status) = model.permissionSyncState else {
            return XCTFail("Expected available permissions")
        }
        XCTAssertTrue(status.isAllowed(for: .inputMonitoring))
        XCTAssertTrue(status.isAllowed(for: .accessibility))
    }

    @MainActor
    func testLaunchAndOrdinaryActivationNeverRequestPermissions() async {
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let agent = ScriptedAgent(states: [
            .success(controlState(enabled: false, permissions: granted)),
            .success(controlState(enabled: true, permissions: granted)),
        ])
        let lifecycle = ScriptedLifecycle()
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()
        await model.applicationDidBecomeActive()

        XCTAssertEqual(agent.requestedGroups, [])
        XCTAssertEqual(lifecycle.ensureCallCount, 0)
        XCTAssertEqual(agent.stateCallCount, 2)
    }

    @MainActor
    func testOrdinaryActivationDuringLaunchDoesNotSupersedeSingleRecovery() async {
        let recoveryStarted = expectation(description: "recovery started")
        let releaseRecovery = DispatchSemaphore(value: 0)
        let expected = controlState(enabled: true)
        let agent = ScriptedAgent(states: [
            .failure(TestError.unavailable),
            .success(expected),
        ])
        let lifecycle = ScriptedLifecycle(ensureHandler: {
            recoveryStarted.fulfill()
            releaseRecovery.wait()
        })
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        let launch = Task { await model.synchronizeOnLaunch() }
        await fulfillment(of: [recoveryStarted], timeout: 1)
        let activation = Task { await model.applicationDidBecomeActive() }
        await Task.yield()
        releaseRecovery.signal()
        await launch.value
        await activation.value

        XCTAssertEqual(lifecycle.ensureCallCount, 1)
        XCTAssertEqual(agent.stateCallCount, 2)
        XCTAssertEqual(model.state, expected)
        XCTAssertEqual(model.permissionSyncState, .available(expected.permissions))
        XCTAssertNil(model.inlineError)
    }

    @MainActor
    func testTemporaryAgentUnavailabilityRecoversOnceAndSucceeds() async {
        let expected = controlState(enabled: true)
        let agent = ScriptedAgent(states: [
            .failure(TestError.unavailable),
            .success(expected),
        ])
        let lifecycle = ScriptedLifecycle()
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(agent.stateCallCount, 2)
        XCTAssertEqual(lifecycle.ensureCallCount, 1)
        XCTAssertEqual(model.state, expected)
        XCTAssertEqual(model.permissionSyncState, .available(expected.permissions))
    }

    @MainActor
    func testCancellationDuringRecoveryStopsWithoutTerminalPublication() async {
        let recoveryStarted = expectation(description: "recovery started")
        let releaseRecovery = DispatchSemaphore(value: 0)
        let agent = ScriptedAgent(states: [
            .failure(TestError.unavailable),
            .success(controlState(enabled: true)),
        ])
        let lifecycle = ScriptedLifecycle(ensureHandler: {
            recoveryStarted.fulfill()
            releaseRecovery.wait()
        })
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        let synchronization = Task { await model.synchronizeOnLaunch() }
        await fulfillment(of: [recoveryStarted], timeout: 1)
        synchronization.cancel()
        releaseRecovery.signal()
        await synchronization.value

        XCTAssertEqual(agent.stateCallCount, 1)
        XCTAssertNil(model.state)
        XCTAssertEqual(model.permissionSyncState, .checking)
        XCTAssertNil(model.inlineError)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testCancellationPreventsAgentCallQueuedOnBackgroundQueue() async {
        let firstStateStarted = expectation(description: "first state started")
        let cancelledOperationStarted = expectation(description: "cancelled operation started")
        let releaseFirstState = DispatchSemaphore(value: 0)
        let agent = ScriptedAgent(stateHandlers: [
            {
                firstStateStarted.fulfill()
                releaseFirstState.wait()
                throw TestError.unavailable
            },
            { controlState(enabled: true) },
        ])
        let model = makeModel(agent: agent)

        let olderOperation = Task { await model.reload() }
        await fulfillment(of: [firstStateStarted], timeout: 1)
        model.onChange = {
            if model.isLoading {
                cancelledOperationStarted.fulfill()
            }
        }
        let cancelledOperation = Task { await model.reload() }
        await fulfillment(of: [cancelledOperationStarted], timeout: 1)
        cancelledOperation.cancel()
        releaseFirstState.signal()
        await olderOperation.value
        await cancelledOperation.value

        XCTAssertEqual(agent.stateCallCount, 1)
        XCTAssertNil(model.state)
        XCTAssertEqual(model.permissionSyncState, .checking)
        XCTAssertNil(model.inlineError)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testFailedRecoveryUsesOneRetryAndClearsStalePermissionState() async {
        let stale = controlState(permissions: permissionStatus(listen: true, post: true, accessibility: true))
        let agent = ScriptedAgent(states: [.success(stale)])
        let model = makeModel(agent: agent)
        await model.reload()
        agent.replaceStates([
            .failure(TestError.unavailable),
            .failure(TestError.unavailable),
        ])

        await model.synchronizeOnLaunch()

        XCTAssertEqual(agent.stateCallCount, 3)
        XCTAssertNil(model.state)
        XCTAssertEqual(model.permissionSyncState, .unavailable)
        XCTAssertEqual(model.inlineError, .agentUnavailable)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testRecoveryFailureQueriesAgentOnceAndPublishesUnavailable() async {
        let agent = ScriptedAgent(states: [.failure(TestError.unavailable)])
        let lifecycle = ScriptedLifecycle(ensureResults: [.failure(TestError.registration)])
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(agent.stateCallCount, 1)
        XCTAssertEqual(lifecycle.ensureCallCount, 1)
        XCTAssertNil(model.state)
        XCTAssertEqual(model.permissionSyncState, .unavailable)
        XCTAssertEqual(model.inlineError, .agentUnavailable)
    }

    @MainActor
    func testAlreadyGrantedPermissionClickDoesNotRequestOrQueryAgain() async {
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let agent = ScriptedAgent(states: [.success(controlState(permissions: granted))])
        let model = makeModel(agent: agent)
        await model.reload()

        await model.requestPermissions(.accessibility)

        XCTAssertEqual(agent.requestedGroups, [])
        XCTAssertEqual(agent.stateCallCount, 1)
    }

    @MainActor
    func testUnknownPermissionClickDoesNotRequest() async {
        let agent = ScriptedAgent(states: [.success(controlState())])
        let model = makeModel(agent: agent)

        await model.requestPermissions(.inputMonitoring)

        XCTAssertEqual(agent.requestedGroups, [])
        XCTAssertEqual(agent.stateCallCount, 0)
    }

    @MainActor
    func testMissingPermissionClickRequestsOnlyGroupThenPublishesFreshState() async {
        let missing = permissionStatus(listen: true, post: false, accessibility: false)
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let calls = LockedCalls()
        let agent = ScriptedAgent(calls: calls, states: [
            .success(controlState(permissions: missing)),
            .success(controlState(permissions: granted)),
        ])
        let model = makeModel(agent: agent)
        await model.reload()
        calls.removeAll()

        await model.requestPermissions(.accessibility)

        XCTAssertEqual(calls.values, ["request:accessibility", "state"])
        XCTAssertEqual(agent.requestedGroups, [.accessibility])
        XCTAssertEqual(model.state?.permissions, granted)
        XCTAssertEqual(model.permissionSyncState, .available(granted))
    }

    @MainActor
    func testSuccessfulUpdateRefreshesPermissionSyncState() async {
        let oldPermissions = permissionStatus(listen: false, post: false, accessibility: false)
        let newPermissions = permissionStatus(listen: true, post: true, accessibility: true)
        let initial = controlState(enabled: false, permissions: oldPermissions)
        let updated = controlState(enabled: true, permissions: newPermissions)
        let agent = ScriptedAgent(states: [.success(initial)], updates: [.success(updated)])
        let model = makeModel(agent: agent)
        await model.reload()

        await model.update(ControlUpdate(enabled: true))

        XCTAssertEqual(model.state, updated)
        XCTAssertEqual(model.permissionSyncState, .available(newPermissions))
        XCTAssertNil(model.inlineError)
    }

    @MainActor
    func testCancelledQueuedOptimisticUpdateStillExecutesAndPublishesAuthoritativeState() async {
        let updateAStarted = expectation(description: "update A started")
        let updateBOptimistic = expectation(description: "update B optimistic")
        let releaseUpdateA = DispatchSemaphore(value: 0)
        let initial = controlState(enabled: false)
        let authoritativeA = controlState(enabled: true)
        let authoritativeB = controlState(
            enabled: false,
            permissions: permissionStatus(listen: true, post: true, accessibility: true)
        )
        let updateA = ControlUpdate(enabled: true)
        let updateB = ControlUpdate(enabled: false)
        let agent = ScriptedAgent(
            stateHandlers: [{ initial }],
            updateHandlers: [
                { _ in
                    updateAStarted.fulfill()
                    releaseUpdateA.wait()
                    return authoritativeA
                },
                { _ in authoritativeB },
            ]
        )
        let model = makeModel(agent: agent)
        await model.reload()

        let taskA = Task { await model.update(updateA) }
        await fulfillment(of: [updateAStarted], timeout: 1)
        model.onChange = {
            if model.state?.enabled == false {
                updateBOptimistic.fulfill()
            }
        }
        let taskB = Task { await model.update(updateB) }
        await fulfillment(of: [updateBOptimistic], timeout: 1)
        model.onChange = nil
        taskB.cancel()
        releaseUpdateA.signal()
        await taskA.value
        await taskB.value

        XCTAssertEqual(agent.receivedUpdates, [updateA, updateB])
        XCTAssertEqual(model.state, authoritativeB)
        XCTAssertEqual(model.permissionSyncState, .available(authoritativeB.permissions))
        XCTAssertNil(model.inlineError)
    }

    @MainActor
    func testFailedUpdatePublishesSynchronizedPermissionState() async {
        let oldPermissions = permissionStatus(listen: false, post: false, accessibility: false)
        let synchronizedPermissions = permissionStatus(listen: true, post: true, accessibility: false)
        let agent = ScriptedAgent(
            states: [
                .success(controlState(permissions: oldPermissions)),
                .success(controlState(permissions: synchronizedPermissions)),
            ],
            updates: [.failure(TestError.update)]
        )
        let model = makeModel(agent: agent)
        await model.reload()

        await model.update(ControlUpdate(enabled: true))

        XCTAssertEqual(model.state?.permissions, synchronizedPermissions)
        XCTAssertEqual(model.permissionSyncState, .available(synchronizedPermissions))
        XCTAssertEqual(model.inlineError, .updateFailed)
    }

    @MainActor
    func testFailedUpdateWithoutSynchronizedStateClearsStalePermission() async {
        let granted = permissionStatus(listen: true, post: true, accessibility: true)
        let agent = ScriptedAgent(
            states: [
                .success(controlState(permissions: granted)),
                .failure(TestError.unavailable),
            ],
            updates: [.failure(TestError.update)]
        )
        let model = makeModel(agent: agent)
        await model.reload()

        await model.update(ControlUpdate(enabled: true))

        XCTAssertNil(model.state)
        XCTAssertEqual(model.permissionSyncState, .unavailable)
        XCTAssertEqual(model.inlineError, .updateFailed)
    }

    @MainActor
    func testOlderInFlightOperationCannotOverwriteNewerState() async {
        let old = controlState(enabled: false)
        let new = controlState(enabled: true)
        let firstStateStarted = expectation(description: "first state started")
        let newerOperationStarted = expectation(description: "newer operation started")
        let releaseFirstState = DispatchSemaphore(value: 0)
        let agent = ScriptedAgent(stateHandlers: [
            {
                firstStateStarted.fulfill()
                releaseFirstState.wait()
                return old
            },
            { new },
        ])
        let model = makeModel(agent: agent)

        let olderTask = Task { await model.reload() }
        await fulfillment(of: [firstStateStarted], timeout: 1)
        model.onChange = {
            if model.isLoading {
                newerOperationStarted.fulfill()
            }
        }
        let newerTask = Task { await model.reload() }
        await fulfillment(of: [newerOperationStarted], timeout: 1)
        releaseFirstState.signal()
        await olderTask.value
        await newerTask.value

        XCTAssertEqual(model.state, new)
        XCTAssertEqual(model.permissionSyncState, .available(new.permissions))
        XCTAssertNil(model.inlineError)
    }

    @MainActor
    func testLifecycleAndAgentCallsRunOffMainThread() async {
        let agent = ScriptedAgent(states: [
            .failure(TestError.unavailable),
            .success(controlState()),
        ])
        let lifecycle = ScriptedLifecycle()
        let model = makeModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(lifecycle.mainThreadObservations, [false])
        XCTAssertEqual(agent.mainThreadObservations, [false, false])
    }

    @MainActor
    private func makeModel(
        agent: ScriptedAgent,
        lifecycle: ScriptedLifecycle = ScriptedLifecycle()
    ) -> ControlViewModel {
        ControlViewModel(
            agent: agent,
            lifecycle: lifecycle
        )
    }
}

private enum TestError: Error {
    case unavailable
    case registration
    case update
}

private func permissionStatus(
    listen: Bool = false,
    post: Bool = false,
    accessibility: Bool = false
) -> EventPermissionStatus {
    EventPermissionStatus(listenEvents: listen, postEvents: post, accessibility: accessibility)
}

private func controlState(
    enabled: Bool = false,
    permissions: EventPermissionStatus = permissionStatus()
) -> ControlState {
    ControlState(
        enabled: enabled,
        historyCount: 2,
        storageBytes: 256,
        configuration: .default,
        permissions: permissions
    )
}

private final class LockedCalls {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func removeAll() {
        lock.withLock { storage.removeAll() }
    }
}

private final class ScriptedAgent: AgentControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let calls: LockedCalls
    private var stateHandlers: [() throws -> ControlState]
    private var updateHandlers: [(ControlUpdate) throws -> ControlState]
    private var receivedUpdateStorage: [ControlUpdate] = []
    private var requestedGroupStorage: [EventPermissionGroup] = []
    private var stateCalls = 0
    private var mainThreadStorage: [Bool] = []

    init(
        calls: LockedCalls = LockedCalls(),
        states: [Result<ControlState, Error>] = [],
        updates: [Result<ControlState, Error>] = []
    ) {
        self.calls = calls
        self.stateHandlers = states.map { result in { try result.get() } }
        self.updateHandlers = updates.map { result in { _ in try result.get() } }
    }

    init(
        calls: LockedCalls = LockedCalls(),
        stateHandlers: [() throws -> ControlState],
        updateHandlers: [(ControlUpdate) throws -> ControlState] = []
    ) {
        self.calls = calls
        self.stateHandlers = stateHandlers
        self.updateHandlers = updateHandlers
    }

    var requestedGroups: [EventPermissionGroup] {
        lock.withLock { requestedGroupStorage }
    }

    var stateCallCount: Int {
        lock.withLock { stateCalls }
    }

    var receivedUpdates: [ControlUpdate] {
        lock.withLock { receivedUpdateStorage }
    }

    var mainThreadObservations: [Bool] {
        lock.withLock { mainThreadStorage }
    }

    func replaceStates(_ states: [Result<ControlState, Error>]) {
        lock.withLock {
            stateHandlers = states.map { result in { try result.get() } }
        }
    }

    func state() throws -> ControlState {
        calls.append("state")
        let handler = try lock.withLock { () throws -> (() throws -> ControlState) in
            stateCalls += 1
            mainThreadStorage.append(Thread.isMainThread)
            guard !stateHandlers.isEmpty else { throw TestError.unavailable }
            return stateHandlers.removeFirst()
        }
        return try handler()
    }

    func update(_ update: ControlUpdate) throws -> ControlState {
        calls.append("update")
        let handler = try lock.withLock { () throws -> ((ControlUpdate) throws -> ControlState) in
            mainThreadStorage.append(Thread.isMainThread)
            receivedUpdateStorage.append(update)
            guard !updateHandlers.isEmpty else { throw TestError.update }
            return updateHandlers.removeFirst()
        }
        return try handler(update)
    }

    func clearHistory() throws {
        calls.append("clear")
    }

    func requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus {
        calls.append("request:\(group.rawValue)")
        lock.withLock {
            mainThreadStorage.append(Thread.isMainThread)
            requestedGroupStorage.append(group)
        }
        return permissionStatus()
    }
}

private final class ScriptedLifecycle: AgentLifecycleControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let calls: LockedCalls
    private var ensureResults: [Result<Void, Error>]
    private var ensureCalls = 0
    private var mainThreadStorage: [Bool] = []
    private let ensureHandler: (() throws -> Void)?

    init(
        calls: LockedCalls = LockedCalls(),
        ensureResults: [Result<Void, Error>] = [.success(())],
        ensureHandler: (() throws -> Void)? = nil
    ) {
        self.calls = calls
        self.ensureResults = ensureResults
        self.ensureHandler = ensureHandler
    }

    var ensureCallCount: Int {
        lock.withLock { ensureCalls }
    }

    var mainThreadObservations: [Bool] {
        lock.withLock { mainThreadStorage }
    }

    func ensureRegisteredAndRunning() throws {
        calls.append("ensure")
        try lock.withLock {
            ensureCalls += 1
            mainThreadStorage.append(Thread.isMainThread)
            guard !ensureResults.isEmpty else { throw TestError.registration }
            try ensureResults.removeFirst().get()
        }
        try ensureHandler?()
    }

    func restartForPermissionRefresh() throws {
        calls.append("restart")
        try lock.withLock {
            mainThreadStorage.append(Thread.isMainThread)
            guard !ensureResults.isEmpty else { throw TestError.registration }
            try ensureResults.removeFirst().get()
        }
        try ensureHandler?()
    }

}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
