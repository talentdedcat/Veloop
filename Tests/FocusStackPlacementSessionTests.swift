import AppKit
import XCTest
@testable import VeloopCore

final class FocusStackPlacementSessionTests: XCTestCase {
    func testDeferredPreparationCapturedBeforeResetDoesNotResolveOrPublish() {
        var resolutions = 0
        let session = FocusStackPlacementSession {
            resolutions += 1
            return NSRect(x: 10, y: 20, width: 30, height: 40)
        }
        let prepare = session.makePreparation()

        session.reset()

        XCTAssertFalse(prepare())
        XCTAssertEqual(resolutions, 0)
        XCTAssertNil(session.frame())
    }

    func testResetDoesNotWaitForInFlightCaretResolutionAndRejectsItsLateResult() {
        let resolutionStarted = expectation(description: "resolution started")
        let allowResolution = DispatchSemaphore(value: 0)
        let preparationFinished = expectation(description: "preparation finished")
        let session = FocusStackPlacementSession {
            resolutionStarted.fulfill()
            allowResolution.wait()
            return NSRect(x: 10, y: 20, width: 30, height: 40)
        }

        DispatchQueue.global().async {
            XCTAssertFalse(session.prepare())
            preparationFinished.fulfill()
        }
        wait(for: [resolutionStarted], timeout: 1)

        let resetFinished = expectation(description: "reset finished")
        DispatchQueue.global().async {
            session.reset()
            resetFinished.fulfill()
        }
        wait(for: [resetFinished], timeout: 0.1)
        allowResolution.signal()
        wait(for: [preparationFinished], timeout: 1)

        XCTAssertNil(session.frame())
    }
}
