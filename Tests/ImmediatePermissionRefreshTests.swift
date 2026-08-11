import Foundation
import XCTest
@testable import VeloopCore

final class ImmediatePermissionRefreshTests: XCTestCase {
    @MainActor
    func testHealthyLaunchPublishesFirstStateWithoutLifecycleCall() async {
        let calls = RefreshCallRecorder()
        let expected = refreshState(enabled: true)
        let agent = RefreshAgent(calls: calls, results: [.success(expected)])
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(calls.values, ["state"])
        XCTAssertEqual(lifecycle.ensureCount, 0)
        XCTAssertEqual(model.state, expected)
    }

    @MainActor
    func testHealthyActivationPublishesFirstStateWithoutLifecycleCall() async {
        let calls = RefreshCallRecorder()
        let expected = refreshState(enabled: true)
        let agent = RefreshAgent(calls: calls, results: [.success(expected)])
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.applicationDidBecomeActive()

        XCTAssertEqual(calls.values, ["state"])
        XCTAssertEqual(lifecycle.ensureCount, 0)
        XCTAssertEqual(model.state, expected)
    }

    @MainActor
    func testDirectSystemSettingsGrantRestartsMissingAgentBeforePublishingFreshState() async {
        let calls = RefreshCallRecorder()
        let missing = ControlState(
            enabled: true,
            historyCount: 1,
            storageBytes: 1,
            configuration: .default,
            permissions: EventPermissionStatus(
                listenEvents: false,
                postEvents: false,
                accessibility: false
            )
        )
        let granted = refreshState(enabled: true)
        let agent = RefreshAgent(
            calls: calls,
            results: [.success(missing), .success(granted)]
        )
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.applicationDidBecomeActive()

        XCTAssertEqual(calls.values, ["state", "restart", "state"])
        XCTAssertEqual(lifecycle.restartCount, 1)
        XCTAssertEqual(model.state, granted)
    }

    @MainActor
    func testReturnFromSystemSettingsRestartsBeforePublishingRevocation() async {
        let calls = RefreshCallRecorder()
        let granted = refreshState(enabled: true)
        let revoked = ControlState(
            enabled: true,
            historyCount: 1,
            storageBytes: 1,
            configuration: .default,
            permissions: EventPermissionStatus(
                listenEvents: false,
                postEvents: false,
                accessibility: false
            )
        )
        let agent = RefreshAgent(
            calls: calls,
            results: [.success(granted), .success(revoked)]
        )
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()
        await model.applicationDidBecomeActive(forcePermissionRefresh: true)

        XCTAssertEqual(calls.values, ["state", "restart", "state"])
        XCTAssertEqual(lifecycle.restartCount, 1)
        XCTAssertEqual(model.state, revoked)
        XCTAssertEqual(model.permissionSyncState, .available(revoked.permissions))
    }

    @MainActor
    func testRepeatedMissingActivationsRestartOnceUntilGrantAppears() async {
        let calls = RefreshCallRecorder()
        let missing = ControlState(
            enabled: true,
            historyCount: 1,
            storageBytes: 1,
            configuration: .default,
            permissions: EventPermissionStatus(
                listenEvents: false,
                postEvents: false,
                accessibility: false
            )
        )
        let granted = refreshState(enabled: true)
        let agent = RefreshAgent(
            calls: calls,
            results: [
                .success(missing),
                .success(missing),
                .success(missing),
                .success(missing),
                .success(granted),
            ]
        )
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()
        await model.applicationDidBecomeActive()
        XCTAssertEqual(model.state, missing)

        await model.applicationDidBecomeActive()

        XCTAssertEqual(lifecycle.restartCount, 2)
        XCTAssertEqual(model.state, granted)
    }

    @MainActor
    func testMissingPermissionRestartsAtMostOncePerActivation() async {
        let calls = RefreshCallRecorder()
        let missing = ControlState(
            enabled: true,
            historyCount: 1,
            storageBytes: 1,
            configuration: .default,
            permissions: EventPermissionStatus(
                listenEvents: false,
                postEvents: false,
                accessibility: false
            )
        )
        let agent = RefreshAgent(
            calls: calls,
            results: Array(repeating: .success(missing), count: 8)
        )
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        for _ in 0..<4 {
            await model.applicationDidBecomeActive()
        }

        XCTAssertEqual(lifecycle.restartCount, 4)
        XCTAssertEqual(model.state, missing)
    }

    @MainActor
    func testFailedFastRequestRecoversOnceThenPublishesFreshState() async {
        let calls = RefreshCallRecorder()
        let expected = refreshState(enabled: true)
        let agent = RefreshAgent(calls: calls, results: [
            .failure(RefreshTestError.unavailable),
            .success(expected),
        ])
        let lifecycle = RefreshLifecycle(calls: calls)
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.synchronizeOnLaunch()

        XCTAssertEqual(calls.values, ["state", "ensure", "state"])
        XCTAssertEqual(lifecycle.ensureCount, 1)
        XCTAssertEqual(model.state, expected)
    }

    @MainActor
    func testFailedRecoveryPublishesUnavailableRatherThanMissing() async {
        let calls = RefreshCallRecorder()
        let agent = RefreshAgent(
            calls: calls,
            results: [.failure(RefreshTestError.unavailable)]
        )
        let lifecycle = RefreshLifecycle(
            calls: calls,
            ensureResult: .failure(RefreshTestError.recoveryFailed)
        )
        let model = ControlViewModel(agent: agent, lifecycle: lifecycle)

        await model.applicationDidBecomeActive()

        XCTAssertEqual(calls.values, ["state", "ensure"])
        XCTAssertEqual(model.permissionSyncState, .unavailable)
        XCTAssertEqual(model.inlineError, .agentUnavailable)
    }
}

private enum RefreshTestError: Error {
    case unavailable
    case recoveryFailed
}

private func refreshState(enabled: Bool) -> ControlState {
    ControlState(
        enabled: enabled,
        historyCount: 1,
        storageBytes: 1,
        configuration: .default,
        permissions: EventPermissionStatus(
            listenEvents: true,
            postEvents: true,
            accessibility: true
        )
    )
}

private final class RefreshCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class RefreshAgent: AgentControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let calls: RefreshCallRecorder
    private var results: [Result<ControlState, Error>]
    init(
        calls: RefreshCallRecorder,
        results: [Result<ControlState, Error>]
    ) {
        self.calls = calls
        self.results = results
    }

    func state() throws -> ControlState {
        calls.append("state")
        lock.lock()
        defer { lock.unlock() }
        guard !results.isEmpty else { throw RefreshTestError.unavailable }
        return try results.removeFirst().get()
    }

    func update(_ update: ControlUpdate) throws -> ControlState { throw RefreshTestError.unavailable }
    func clearHistory() throws { throw RefreshTestError.unavailable }
}

private final class RefreshLifecycle: AgentLifecycleControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let calls: RefreshCallRecorder
    private let ensureResult: Result<Void, Error>
    private var ensures = 0
    private var restarts = 0

    init(
        calls: RefreshCallRecorder,
        ensureResult: Result<Void, Error> = .success(())
    ) {
        self.calls = calls
        self.ensureResult = ensureResult
    }

    var ensureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return ensures
    }

    var restartCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return restarts
    }

    func ensureRegisteredAndRunning() throws {
        calls.append("ensure")
        lock.lock()
        ensures += 1
        lock.unlock()
        try ensureResult.get()
    }

    func restartForPermissionRefresh() throws {
        calls.append("restart")
        lock.lock()
        restarts += 1
        lock.unlock()
        try ensureResult.get()
    }

}
