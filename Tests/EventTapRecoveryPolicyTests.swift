import CoreGraphics
import XCTest
@testable import VeloopCore

final class EventTapRecoveryPolicyTests: XCTestCase {
    func testOnlyTimeoutDisableMayReenableTheEventTap() {
        XCTAssertTrue(EventTapManager.shouldReenable(after: .tapDisabledByTimeout))
        XCTAssertFalse(EventTapManager.shouldReenable(after: .tapDisabledByUserInput))
    }

    func testUserInputDisableNotifiesTheRuntimeAfterStopping() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Core/Input/EventTapManager.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("onUnexpectedStop"))
        XCTAssertTrue(source.contains("self?.stop()"))
        XCTAssertTrue(source.contains("self?.onUnexpectedStop()"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
