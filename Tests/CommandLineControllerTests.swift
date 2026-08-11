import XCTest
@testable import VeloopCore

final class CommandLineControllerTests: XCTestCase {
    func testUnsupportedRestartReturnsUsageWithoutAgentRequest() {
        let requester = CommandRequester()
        let controller = makeController(requester: requester)

        let result = controller.run(arguments: ["restart"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertFalse(result.standardError.contains("restart"))
        XCTAssertEqual(requester.callCount, 0)
    }

    func testUnavailableAgentDoesNotRecommendUnsupportedRestart() {
        let requester = CommandRequester(error: AgentClientError.agentUnavailable)
        let controller = makeController(requester: requester)

        let result = controller.run(arguments: ["status"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(
            result.standardError,
            "Veloop is not running. Open Veloop from /Applications and try again.\n"
        )
        XCTAssertFalse(result.standardError.contains("restart"))
        XCTAssertEqual(requester.callCount, 1)
    }

    private func makeController(requester: AgentRequesting) -> CommandLineController {
        CommandLineController(
            requester: requester,
            openDataDirectory: { false },
            uninstallPurge: {}
        )
    }
}

private final class CommandRequester: AgentRequesting, @unchecked Sendable {
    private let error: Error?
    private(set) var callCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func send(_ request: AgentRequest) throws -> AgentResponse {
        callCount += 1
        if let error {
            throw error
        }
        return .success("ok")
    }
}
