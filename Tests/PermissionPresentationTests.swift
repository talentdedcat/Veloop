import XCTest
@testable import VeloopCore

final class PermissionPresentationTests: XCTestCase {
    func testFullyGrantedAgentResponseDisplaysBothRowsAsAllowed() {
        let state = PermissionSyncState.available(
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: true)
        )

        XCTAssertEqual(state.displayState(for: .inputMonitoring), .allowed)
        XCTAssertEqual(state.displayState(for: .accessibility), .allowed)
    }

    func testAccessibilityRequiresPostingAndAXPermission() {
        let state = PermissionSyncState.available(
            EventPermissionStatus(listenEvents: true, postEvents: false, accessibility: true)
        )

        XCTAssertEqual(state.displayState(for: .inputMonitoring), .allowed)
        XCTAssertEqual(state.displayState(for: .accessibility), .missing)
    }

    func testAvailableDeniedPermissionDisplaysAsMissing() {
        let state = PermissionSyncState.available(
            EventPermissionStatus(listenEvents: false, postEvents: true, accessibility: true)
        )

        XCTAssertEqual(state.displayState(for: .inputMonitoring), .missing)
    }

    func testCheckingAndUnavailableNeverDisplayAsMissing() {
        for group in [EventPermissionGroup.inputMonitoring, .accessibility] {
            XCTAssertEqual(PermissionSyncState.checking.displayState(for: group), .checking)
            XCTAssertEqual(PermissionSyncState.unavailable.displayState(for: group), .unavailable)
        }
    }

    func testPermissionDisplayStateIsEquatableAndSendable() {
        XCTAssertEqual(PermissionDisplayState.allowed, .allowed)
        assertSendable(PermissionDisplayState.checking)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
