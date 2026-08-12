import Foundation
import XCTest
@testable import VeloopCore

final class PasteCycleControllerTests: XCTestCase {
    func testCommandVDoesNotWaitForDeferredCyclePreparation() throws {
        let snapshotID = UUID()
        var finishPreparation: (([UUID]?) -> Void)?
        var presentations: [PasteCyclePresentationEvent] = []
        let controller = PasteCycleController(
            historyIDs: { XCTFail("history must be read by deferred preparation"); return [] },
            canCycle: { true },
            prepareCycle: { finishPreparation = $0 },
            present: { presentations.append($0) },
            commit: { _ in XCTFail("must not commit while preparing") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        XCTAssertFalse(controller.isCycling)
        XCTAssertTrue(presentations.isEmpty)

        try XCTUnwrap(finishPreparation)([snapshotID])

        XCTAssertTrue(controller.isCycling)
        XCTAssertEqual(presentations, [
            .selected(PasteCycleSelection(
                selectedID: snapshotID,
                newerID: nil,
                olderID: nil,
                index: 0,
                count: 1,
                direction: .older
            )),
        ])
    }

    func testFailedDeferredPreparationFallsBackToOrdinaryPaste() throws {
        var finishPreparation: (([UUID]?) -> Void)?
        var fallbackPasteCount = 0
        var presentations: [PasteCyclePresentationEvent] = []
        let controller = PasteCycleController(
            historyIDs: { [] },
            canCycle: { true },
            prepareCycle: { finishPreparation = $0 },
            present: { presentations.append($0) },
            fallbackPaste: { fallbackPasteCount += 1 },
            commit: { _ in XCTFail("failed preparation must not commit history") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        try XCTUnwrap(finishPreparation)(nil)

        XCTAssertEqual(fallbackPasteCount, 1)
        XCTAssertEqual(presentations, [.interrupted])
        XCTAssertFalse(controller.isCycling)
    }

    func testCommandReleaseDuringPreparationPastesNormallyAndIgnoresLateResult() throws {
        let snapshotID = UUID()
        var finishPreparation: (([UUID]?) -> Void)?
        var fallbackPasteCount = 0
        var presentations: [PasteCyclePresentationEvent] = []
        let controller = PasteCycleController(
            historyIDs: { [] },
            canCycle: { true },
            prepareCycle: { finishPreparation = $0 },
            present: { presentations.append($0) },
            fallbackPaste: { fallbackPasteCount += 1 },
            commit: { _ in XCTFail("cancelled preparation must not commit history") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        XCTAssertFalse(controller.handle(.commandReleased))
        XCTAssertEqual(fallbackPasteCount, 1)
        XCTAssertEqual(presentations, [.interrupted])

        try XCTUnwrap(finishPreparation)([snapshotID])

        XCTAssertEqual(fallbackPasteCount, 1)
        XCTAssertEqual(presentations, [.interrupted])
        XCTAssertFalse(controller.isCycling)
    }

    func testPermissionLossDuringPreparationRestoresSuppressedPaste() throws {
        var permissionAvailable = true
        var finishPreparation: (([UUID]?) -> Void)?
        var fallbackPasteCount = 0
        let controller = PasteCycleController(
            historyIDs: { [] },
            canCycle: { permissionAvailable },
            canContinueCycle: { permissionAvailable },
            prepareCycle: { finishPreparation = $0 },
            fallbackPaste: { fallbackPasteCount += 1 },
            commit: { _ in XCTFail("permission loss must not commit history") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        permissionAvailable = false
        XCTAssertFalse(controller.handle(.vKeyUp))
        XCTAssertEqual(fallbackPasteCount, 1)

        try XCTUnwrap(finishPreparation)([UUID()])
        XCTAssertEqual(fallbackPasteCount, 1)
    }

    func testNavigationIsSuppressedWhileCyclePreparationIsInFlight() {
        let controller = PasteCycleController(
            historyIDs: { [] },
            canCycle: { true },
            prepareCycle: { _ in },
            commit: { _ in XCTFail("must not commit while preparing") }
        )

        XCTAssertTrue(controller.handle(.commandV))
        XCTAssertTrue(controller.handle(.move(.older)))
        XCTAssertTrue(controller.handle(.move(.newer)))
        XCTAssertTrue(controller.handle(.navigationKeyUp))
    }

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
