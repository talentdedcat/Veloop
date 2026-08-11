import Darwin
import Foundation
import XCTest
@testable import VeloopCore

final class AgentProtocolTests: XCTestCase {
    func testObsoletePermissionRequestIPCIsRemoved() throws {
        let combinedSource = try [
            "Sources/Core/Permissions/EventPermissionController.swift",
            "Sources/Core/Control/ControlState.swift",
            "Sources/Core/Control/ControlViewModel.swift",
            "Sources/Core/Control/AgentControlClient.swift",
            "Sources/Core/Agent/VeloopAgentRuntime.swift",
        ].map(source).joined(separator: "\n")

        for obsolete in ["EventPermissionGroup", "requestPermissions", "request-permissions"] {
            XCTAssertFalse(combinedSource.contains(obsolete), obsolete)
        }
    }

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

    func testControlStateSynchronizesInputFromTheSamePermissionSnapshot() throws {
        let runtime = try source("Sources/Core/Agent/VeloopAgentRuntime.swift")
        let start = try XCTUnwrap(runtime.range(of: "private func controlState()"))
        let end = try XCTUnwrap(runtime.range(
            of: "\n    private func applyControlUpdate",
            range: start.lowerBound..<runtime.endIndex
        ))
        let body = runtime[start.lowerBound..<end.lowerBound]

        XCTAssertEqual(body.components(separatedBy: "permissions.status()").count - 1, 1)
        XCTAssertTrue(body.contains("synchronizeInputSubsystemOnMain(permissionStatus)"))
        XCTAssertTrue(body.contains("permissions: permissionStatus"))
    }

    func testRuntimeNoLongerOwnsAgentRestart() throws {
        let runtime = try source("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertFalse(runtime.contains("case \"restart\":"))
        XCTAssertFalse(runtime.contains("AgentProcessRestarter"))
        XCTAssertFalse(exists("Sources/Core/Agent/AgentProcessRestarter.swift"))
    }

    func testPermissionControllerHasNoRequestAPI() throws {
        let controller = try source("Sources/Core/Permissions/EventPermissionController.swift")

        XCTAssertFalse(controller.contains("func request"))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
