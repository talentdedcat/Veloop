import XCTest
@testable import VeloopCore

final class NumericVersionTests: XCTestCase {
    func testComparesComponentsNumerically() throws {
        XCTAssertGreaterThan(try NumericVersion("0.2.4"), try NumericVersion("0.2.3"))
        XCTAssertGreaterThan(try NumericVersion("0.2.10"), try NumericVersion("0.2.9"))
    }

    func testTrailingZeroComponentsAreEquivalent() throws {
        XCTAssertEqual(try NumericVersion("0.2.3"), try NumericVersion("0.2.3.0"))
    }

    func testRejectsNonNumericOrIncompleteVersions() {
        for value in ["", " ", "-1.0", "+1.0", "1.a", "1..0", ".1", "1."] {
            XCTAssertThrowsError(try NumericVersion(value), value)
        }
    }
}
