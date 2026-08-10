import XCTest
@testable import VeloopCore

final class AppLaunchModeTests: XCTestCase {
    func testLaunchModeAcceptsOnlyControlAndAgentForms() {
        XCTAssertEqual(AppLaunchMode(arguments: []), .control)
        XCTAssertEqual(AppLaunchMode(arguments: ["--agent"]), .agent)
        XCTAssertEqual(AppLaunchMode(arguments: ["--agent", "extra"]), .invalid)
        XCTAssertEqual(AppLaunchMode(arguments: ["--unknown"]), .invalid)
    }
}
