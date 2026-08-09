import Darwin
import Foundation
import XCTest
@testable import VeloopCore

final class AgentProtocolTests: XCTestCase {
    func testRequestAndResponseRoundTrip() throws {
        let request = AgentRequest(command: "config-set", arguments: ["maximumHistoryCount", "200"])
        let response = AgentResponse.success("ok")

        XCTAssertEqual(try AgentProtocolCodec.decodeRequest(AgentProtocolCodec.encode(request)), request)
        XCTAssertEqual(try AgentProtocolCodec.decodeResponse(AgentProtocolCodec.encode(response)), response)
    }

    func testOversizedMessageIsRejected() {
        let oversized = Data(repeating: 0x61, count: AgentProtocolCodec.maximumMessageBytes + 1)

        XCTAssertThrowsError(try AgentProtocolCodec.decodeRequest(oversized)) { error in
            XCTAssertEqual(error as? AgentProtocolError, .messageTooLarge)
        }
    }

    func testUnixSocketServerAndClientRoundTrip() throws {
        let root = try temporaryDirectory()
        let socketURL = root.appendingPathComponent("agent.sock")
        let server = AgentServer(socketURL: socketURL) { request in
            .success("\(request.command):\(request.arguments.joined(separator: ","))")
        }
        try server.start()
        addTeardownBlock { server.stop() }

        let response = try AgentClient(socketURL: socketURL).send(
            AgentRequest(command: "count", arguments: ["one"])
        )

        XCTAssertEqual(response, .success("count:one"))
        let permissions = try FileManager.default.attributesOfItem(atPath: socketURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testUnavailableAgentProducesClearError() throws {
        let root = try temporaryDirectory()
        let client = AgentClient(socketURL: root.appendingPathComponent("missing.sock"))

        XCTAssertThrowsError(try client.send(AgentRequest(command: "status", arguments: []))) { error in
            XCTAssertEqual(error as? AgentClientError, .agentUnavailable)
        }
    }

    func testStalledClientTimesOutWithoutBlockingFollowingRequest() throws {
        let root = try temporaryDirectory()
        let socketURL = root.appendingPathComponent("agent.sock")
        let server = AgentServer(
            socketURL: socketURL,
            clientTimeoutMilliseconds: 100
        ) { _ in
            .success("ok")
        }
        try server.start()
        addTeardownBlock { server.stop() }

        let stalledDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(stalledDescriptor, 0)
        addTeardownBlock { Darwin.close(stalledDescriptor) }
        let connectionStatus = try withUnixAddress(path: socketURL.path) { address, length in
            Darwin.connect(stalledDescriptor, address, length)
        }
        XCTAssertEqual(connectionStatus, 0)

        let started = Date()
        let response = try AgentClient(socketURL: socketURL).send(
            AgentRequest(command: "status", arguments: [])
        )

        XCTAssertEqual(response, .success("ok"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
