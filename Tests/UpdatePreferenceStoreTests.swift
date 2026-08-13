import XCTest
@testable import VeloopCore

final class UpdatePreferenceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: UpdatePreferenceStore!

    override func setUp() {
        super.setUp()
        let suite = "UpdatePreferenceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = UpdatePreferenceStore(defaults: defaults)
    }

    func testAutomaticCheckBecomesDueAtTwentyFourHours() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.isAutomaticCheckDue(at: start))

        store.recordAutomaticAttempt(at: start)

        XCTAssertFalse(store.isAutomaticCheckDue(at: start.addingTimeInterval(86_399)))
        XCTAssertTrue(store.isAutomaticCheckDue(at: start.addingTimeInterval(86_400)))
    }

    func testFutureAutomaticAttemptDoesNotSuppressChecksAfterClockMovesBackward() {
        let now = Date(timeIntervalSince1970: 1_000)
        store.recordAutomaticAttempt(at: now.addingTimeInterval(86_400))

        XCTAssertTrue(store.isAutomaticCheckDue(at: now))
    }

    func testClockRollbackDoesNotExtendRemindLaterBeyondOneDay() throws {
        let version = try NumericVersion("0.3.0")
        let now = Date(timeIntervalSince1970: 1_000)
        store.remindLater(about: version, at: now.addingTimeInterval(86_400))

        XCTAssertFalse(store.isDeferred(version, at: now))
    }

    func testSkipAndDeferralApplyOnlyToMatchingVersion() throws {
        let current = try NumericVersion("0.2.4")
        let newer = try NumericVersion("0.2.5")
        let now = Date(timeIntervalSince1970: 2_000)

        store.skip(current)
        XCTAssertTrue(store.isSkipped(current))
        XCTAssertFalse(store.isSkipped(newer))

        store.remindLater(about: current, at: now)
        XCTAssertTrue(store.isDeferred(current, at: now.addingTimeInterval(86_399)))
        XCTAssertFalse(store.isDeferred(current, at: now.addingTimeInterval(86_400)))
        XCTAssertFalse(store.isDeferred(newer, at: now))
    }

    func testDownloadDoesNotChangeSuppressionState() throws {
        let version = try NumericVersion("0.2.4")
        store.record(.download, for: version, at: Date())
        XCTAssertFalse(store.isSkipped(version))
        XCTAssertFalse(store.isDeferred(version, at: Date()))
    }

    func testRemindLaterReplacesSkipForTheSameRelease() throws {
        let version = try NumericVersion("0.2.4")
        let now = Date(timeIntervalSince1970: 3_000)
        store.record(.skip, for: version, at: now)

        store.record(.remindLater, for: version, at: now)

        XCTAssertFalse(store.isSkipped(version))
        XCTAssertTrue(store.isDeferred(version, at: now))
    }

    func testSkipReplacesDeferralForTheSameRelease() throws {
        let version = try NumericVersion("0.2.4")
        let now = Date(timeIntervalSince1970: 4_000)
        store.record(.remindLater, for: version, at: now)

        store.record(.skip, for: version, at: now)

        XCTAssertTrue(store.isSkipped(version))
        XCTAssertFalse(store.isDeferred(version, at: now))
    }
}
