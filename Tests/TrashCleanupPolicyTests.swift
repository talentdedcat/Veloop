import Foundation
import XCTest
@testable import VeloopCore

final class TrashCleanupPolicyTests: XCTestCase {
    func testMissingPreferenceDefaultsToPreserveUserData() {
        let suiteName = "TrashCleanupPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            TrashCleanupPreferenceStore(defaults: defaults).policy,
            .preserveUserData
        )
    }

    func testPreferencePersistsBothChoices() {
        let suiteName = "TrashCleanupPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TrashCleanupPreferenceStore(defaults: defaults)

        store.policy = .purgeUserData
        XCTAssertEqual(
            TrashCleanupPreferenceStore(defaults: defaults).policy,
            .purgeUserData
        )

        store.policy = .preserveUserData
        XCTAssertEqual(
            TrashCleanupPreferenceStore(defaults: defaults).policy,
            .preserveUserData
        )
    }
}
