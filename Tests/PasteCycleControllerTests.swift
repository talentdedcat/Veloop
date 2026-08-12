import Foundation
import XCTest
@testable import VeloopCore

final class PasteCycleControllerTests: XCTestCase {
    func testPermissionLossBeforeKeyUpInterruptsCycleAndPassesEventThrough() {
        var permissionAvailable = true
        var presentations: [PasteCyclePresentationEvent] = []
        let controller = PasteCycleController(
            historyIDs: { [UUID()] },
            canCycle: { permissionAvailable },
            canContinueCycle: { permissionAvailable },
            present: { presentations.append($0) },
            commit: { _ in XCTFail("must not commit after permission loss") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        permissionAvailable = false

        XCTAssertFalse(controller.handle(.vKeyUp))
        XCTAssertFalse(controller.isCycling)
        XCTAssertEqual(presentations.last, .interrupted)
    }

    func testPermissionLossBeforeCommandReleaseDoesNotCommit() {
        var permissionAvailable = true
        let noCommit = expectation(description: "no commit")
        noCommit.isInverted = true
        let controller = PasteCycleController(
            historyIDs: { [UUID()] },
            canCycle: { permissionAvailable },
            canContinueCycle: { permissionAvailable },
            commit: { _ in noCommit.fulfill() }
        )

        XCTAssertTrue(controller.handle(.commandV))
        permissionAvailable = false
        XCTAssertFalse(controller.handle(.commandReleased))

        wait(for: [noCommit], timeout: 0.05)
        XCTAssertFalse(controller.isCycling)
    }
}
