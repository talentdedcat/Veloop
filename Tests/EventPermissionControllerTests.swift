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

    func testCompatibilityRequestOnlyReturnsFreshPreflightStatus() {
        let spy = PermissionSpy(listenEvents: false, postEvents: false, accessibility: false)
        let controller = spy.makeController()

        spy.listenEvents = true
        spy.postEvents = true
        spy.accessibility = true

        let status = controller.request(.accessibility)

        XCTAssertEqual(
            status,
            EventPermissionStatus(listenEvents: true, postEvents: true, accessibility: true)
        )
        XCTAssertEqual(spy.listenPreflightCount, 1)
        XCTAssertEqual(spy.postPreflightCount, 1)
        XCTAssertEqual(spy.accessibilityPreflightCount, 1)
    }
}

private final class PermissionSpy {
    var listenEvents: Bool
    var postEvents: Bool
    var accessibility: Bool

    var listenPreflightCount = 0
    var postPreflightCount = 0
    var accessibilityPreflightCount = 0
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
            }
        )
    }
}
