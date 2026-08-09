import XCTest
@testable import VeloopCore

final class PaletteInputSourceActivatorTests: XCTestCase {
    func testMissingSourceReportsFullyInactiveStatus() {
        XCTAssertEqual(
            PaletteInputSourceActivator.status(for: nil),
            PaletteInputSourceStatus(installed: false, enabled: false, selected: false)
        )
    }

    func testStartupRetriesAreFiniteAndCompleteWithinTenSeconds() {
        let delays = PaletteInputSourceActivator.startupRetryDelaysNanoseconds

        XCTAssertEqual(delays.first, 0)
        XCTAssertEqual(delays.count, 6)
        XCTAssertLessThanOrEqual(delays.reduce(0, +), 10_000_000_000)
        XCTAssertEqual(delays, delays.sorted())
    }
}
