import XCTest
@testable import VeloopCore

final class PermissionPresentationTests: XCTestCase {
    func testFullyGrantedAgentResponseDisplaysAllowed() {
        let state = PermissionSyncState.available(
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: true)
        )

        XCTAssertEqual(state.displayState, .allowed)
    }

    func testAccessibilityDisplayRequiresEveryRuntimeCapability() {
        for status in [
            EventPermissionStatus(listenEvents: false, postEvents: true, accessibility: true),
            EventPermissionStatus(listenEvents: true, postEvents: false, accessibility: true),
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: false),
        ] {
            XCTAssertEqual(PermissionSyncState.available(status).displayState, .missing)
        }
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
