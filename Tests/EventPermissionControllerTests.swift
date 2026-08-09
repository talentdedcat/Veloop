import XCTest
@testable import VeloopCore

final class EventPermissionControllerTests: XCTestCase {
    func testPermissionGroupHasStableCodableRawValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(EventPermissionGroup.inputMonitoring.rawValue, "inputMonitoring")
        XCTAssertEqual(EventPermissionGroup.accessibility.rawValue, "accessibility")
        XCTAssertEqual(
            try decoder.decode(EventPermissionGroup.self, from: encoder.encode(EventPermissionGroup.inputMonitoring)),
            .inputMonitoring
        )
    }

    func testStatusAllowanceMatchesEachPermissionGroup() {
        XCTAssertTrue(
            EventPermissionStatus(listenEvents: true, postEvents: false, accessibility: false)
                .isAllowed(for: .inputMonitoring)
        )
        XCTAssertFalse(
            EventPermissionStatus(listenEvents: false, postEvents: true, accessibility: true)
                .isAllowed(for: .inputMonitoring)
        )
        XCTAssertTrue(
            EventPermissionStatus(listenEvents: false, postEvents: true, accessibility: true)
                .isAllowed(for: .accessibility)
        )
        XCTAssertFalse(
            EventPermissionStatus(listenEvents: true, postEvents: false, accessibility: true)
                .isAllowed(for: .accessibility)
        )
        XCTAssertFalse(
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: false)
                .isAllowed(for: .accessibility)
        )
    }

    func testStatusReadsEveryPreflightOnEveryCall() {
        let spy = PermissionSpy(listenEvents: false, postEvents: false, accessibility: false)
        let controller = spy.makeController()

        XCTAssertEqual(
            controller.status(),
            EventPermissionStatus(listenEvents: false, postEvents: false, accessibility: false)
        )
        spy.listenEvents = true
        spy.postEvents = true
        spy.accessibility = true

        XCTAssertEqual(
            controller.status(),
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: true)
        )
        XCTAssertEqual(spy.listenPreflightCount, 2)
        XCTAssertEqual(spy.postPreflightCount, 2)
        XCTAssertEqual(spy.accessibilityPreflightCount, 2)
    }

    func testInputMonitoringRequestPromptsOnlyForMissingListenAccessAndReturnsFreshStatus() {
        let spy = PermissionSpy(listenEvents: false, postEvents: false, accessibility: false)
        spy.onRequestListen = { spy.listenEvents = true }
        let controller = spy.makeController()

        let status = controller.request(.inputMonitoring)

        XCTAssertEqual(spy.listenRequestCount, 1)
        XCTAssertEqual(spy.postRequestCount, 0)
        XCTAssertEqual(spy.accessibilityRequestCount, 0)
        XCTAssertEqual(spy.listenPreflightCount, 2)
        XCTAssertEqual(spy.postPreflightCount, 2)
        XCTAssertEqual(spy.accessibilityPreflightCount, 2)
        XCTAssertEqual(
            status,
            EventPermissionStatus(listenEvents: true, postEvents: false, accessibility: false)
        )
    }

    func testInputMonitoringRequestDoesNotPromptWhenGroupIsAlreadyGranted() {
        let spy = PermissionSpy(listenEvents: true, postEvents: false, accessibility: false)

        let status = spy.makeController().request(.inputMonitoring)

        XCTAssertEqual(spy.listenRequestCount, 0)
        XCTAssertEqual(spy.postRequestCount, 0)
        XCTAssertEqual(spy.accessibilityRequestCount, 0)
        XCTAssertTrue(status.isAllowed(for: .inputMonitoring))
    }

    func testAccessibilityRequestPromptsForMissingPostAndAccessibilityAccessAndReturnsFreshStatus() {
        let spy = PermissionSpy(listenEvents: false, postEvents: false, accessibility: false)
        spy.onRequestPost = { spy.postEvents = true }
        spy.onRequestAccessibility = { spy.accessibility = true }
        let controller = spy.makeController()

        let status = controller.request(.accessibility)

        XCTAssertEqual(spy.listenRequestCount, 0)
        XCTAssertEqual(spy.postRequestCount, 1)
        XCTAssertEqual(spy.accessibilityRequestCount, 1)
        XCTAssertEqual(
            status,
            EventPermissionStatus(listenEvents: false, postEvents: true, accessibility: true)
        )
    }

    func testAccessibilityRequestPromptsOnlyForMissingChecks() {
        let cases: [(postEvents: Bool, accessibility: Bool, expectedPost: Int, expectedAccessibility: Int)] = [
            (true, false, 0, 1),
            (false, true, 1, 0),
        ]

        for testCase in cases {
            let spy = PermissionSpy(
                listenEvents: false,
                postEvents: testCase.postEvents,
                accessibility: testCase.accessibility
            )

            _ = spy.makeController().request(.accessibility)

            XCTAssertEqual(spy.listenRequestCount, 0)
            XCTAssertEqual(spy.postRequestCount, testCase.expectedPost)
            XCTAssertEqual(spy.accessibilityRequestCount, testCase.expectedAccessibility)
        }
    }

    func testAccessibilityRequestDoesNotPromptWhenGroupIsAlreadyGranted() {
        let spy = PermissionSpy(listenEvents: false, postEvents: true, accessibility: true)

        let status = spy.makeController().request(.accessibility)

        XCTAssertEqual(spy.listenRequestCount, 0)
        XCTAssertEqual(spy.postRequestCount, 0)
        XCTAssertEqual(spy.accessibilityRequestCount, 0)
        XCTAssertTrue(status.isAllowed(for: .accessibility))
    }
}

private final class PermissionSpy {
    var listenEvents: Bool
    var postEvents: Bool
    var accessibility: Bool

    var listenPreflightCount = 0
    var postPreflightCount = 0
    var accessibilityPreflightCount = 0
    var listenRequestCount = 0
    var postRequestCount = 0
    var accessibilityRequestCount = 0

    var onRequestListen: () -> Void = {}
    var onRequestPost: () -> Void = {}
    var onRequestAccessibility: () -> Void = {}

    init(listenEvents: Bool, postEvents: Bool, accessibility: Bool) {
        self.listenEvents = listenEvents
        self.postEvents = postEvents
        self.accessibility = accessibility
    }

    func makeController() -> EventPermissionController {
        EventPermissionController(
            preflightListenEventAccess: {
                self.listenPreflightCount += 1
                return self.listenEvents
            },
            preflightPostEventAccess: {
                self.postPreflightCount += 1
                return self.postEvents
            },
            preflightAccessibility: {
                self.accessibilityPreflightCount += 1
                return self.accessibility
            },
            requestListenEventAccess: {
                self.listenRequestCount += 1
                self.onRequestListen()
                return self.listenEvents
            },
            requestPostEventAccess: {
                self.postRequestCount += 1
                self.onRequestPost()
                return self.postEvents
            },
            requestAccessibility: {
                self.accessibilityRequestCount += 1
                self.onRequestAccessibility()
                return self.accessibility
            }
        )
    }
}
