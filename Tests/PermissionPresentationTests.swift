import XCTest
@testable import VeloopCore

final class PermissionPresentationTests: XCTestCase {
    func testFullyGrantedAgentResponseDisplaysAllowed() {
        let state = PermissionSyncState.available(
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: true)
        )

        XCTAssertEqual(state.displayState, .allowed)
    }

    func testAccessibilityDisplayIgnoresLegacyEventPreflights() {
        let accessibilityOnly = EventPermissionStatus(
            listenEvents: false,
            postEvents: false,
            accessibility: true
        )
        let missingAccessibility = EventPermissionStatus(
            listenEvents: true,
            postEvents: true,
            accessibility: false
        )

        XCTAssertEqual(PermissionSyncState.available(accessibilityOnly).displayState, .allowed)
        XCTAssertEqual(PermissionSyncState.available(missingAccessibility).displayState, .missing)
    }

    func testCheckingAndUnavailableNeverDisplayAsMissing() {
        XCTAssertEqual(PermissionSyncState.checking.displayState, .checking)
        XCTAssertEqual(PermissionSyncState.unavailable.displayState, .unavailable)
    }

    func testPermissionDisplayStateIsEquatableAndSendable() {
        XCTAssertEqual(PermissionDisplayState.allowed, .allowed)
        assertSendable(PermissionDisplayState.checking)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
