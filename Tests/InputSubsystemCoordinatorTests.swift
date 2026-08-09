import XCTest
@testable import VeloopCore

final class InputSubsystemCoordinatorTests: XCTestCase {
    @MainActor
    func testRunsOnlyWhenEnabledAndListenPermissionAreBothTrue() {
        let cases: [(enabled: Bool, allowed: Bool, expected: [String])] = [
            (false, false, ["stop", "deactivate"]),
            (false, true, ["stop", "deactivate"]),
            (true, false, ["stop", "deactivate"]),
            (true, true, ["start", "activate"]),
        ]

        for testCase in cases {
            var events: [String] = []
            let coordinator = InputSubsystemCoordinator(
                startListening: {
                    events.append("start")
                    return true
                },
                stopListening: { events.append("stop") },
                activatePalette: {
                    events.append("activate")
                    return Task {}
                },
                deactivatePalette: { events.append("deactivate") }
            )

            coordinator.synchronize(
                enabled: testCase.enabled,
                listenEvents: testCase.allowed
            )

            XCTAssertEqual(events, testCase.expected)
        }
    }

    @MainActor
    func testRepeatedRunningAndStoppedStatesAreIdempotent() {
        var events: [String] = []
        let coordinator = InputSubsystemCoordinator(
            startListening: {
                events.append("start")
                return true
            },
            stopListening: { events.append("stop") },
            activatePalette: {
                events.append("activate")
                return Task {}
            },
            deactivatePalette: { events.append("deactivate") }
        )

        coordinator.synchronize(enabled: true, listenEvents: true)
        coordinator.synchronize(enabled: true, listenEvents: true)
        coordinator.synchronize(enabled: false, listenEvents: true)
        coordinator.synchronize(enabled: false, listenEvents: false)

        XCTAssertEqual(events, ["start", "activate", "stop", "deactivate"])
    }

    @MainActor
    func testListenerStartFailureLeavesPaletteStopped() {
        var events: [String] = []
        let coordinator = InputSubsystemCoordinator(
            startListening: {
                events.append("start")
                return false
            },
            stopListening: { events.append("stop") },
            activatePalette: {
                events.append("activate")
                return Task {}
            },
            deactivatePalette: { events.append("deactivate") }
        )

        coordinator.synchronize(enabled: true, listenEvents: true)
        coordinator.synchronize(enabled: false, listenEvents: true)

        XCTAssertEqual(events, ["start", "stop", "deactivate"])
    }
}
