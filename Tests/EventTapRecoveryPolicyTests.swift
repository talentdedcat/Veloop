import CoreGraphics
import XCTest
@testable import VeloopCore

final class EventTapRecoveryPolicyTests: XCTestCase {
    func testOnlyTimeoutDisableMayReenableTheEventTap() {
        XCTAssertTrue(EventTapManager.shouldReenable(after: .tapDisabledByTimeout))
        XCTAssertFalse(EventTapManager.shouldReenable(after: .tapDisabledByUserInput))
    }
}
