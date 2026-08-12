import XCTest
@testable import VeloopCore

final class PermissionRecoveryMonitorTests: XCTestCase {
    @MainActor
    func testStopsCheckingAsSoonAsAllPermissionsRecover() {
        var statuses = [missingPermissionStatus, allowedPermissionStatus]
        var recovered: [EventPermissionStatus] = []
        let monitor = PermissionRecoveryMonitor(
            readStatus: { statuses.removeFirst() },
            onRecovered: { recovered.append($0) }
        )

        XCTAssertFalse(monitor.checkNow())
        XCTAssertTrue(monitor.checkNow())
        XCTAssertEqual(recovered, [allowedPermissionStatus])
    }

    @MainActor
    func testRecoveryPollingUsesShortBoundedInterval() {
        XCTAssertEqual(PermissionRecoveryMonitor.intervalMilliseconds, 100)
    }

    private var missingPermissionStatus: EventPermissionStatus {
        EventPermissionStatus(listenEvents: false, postEvents: false, accessibility: false)
    }

    private var allowedPermissionStatus: EventPermissionStatus {
        EventPermissionStatus(listenEvents: false, postEvents: false, accessibility: true)
    }
}
