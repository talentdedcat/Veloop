import Darwin
import Foundation
import XCTest
@testable import VeloopCore

final class AgentClientDeadlineTests: XCTestCase {
    func testClientReadDeadlineBoundsAConnectedServerThatNeverResponds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vac-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("stalled.sock")
        let server = try StalledUnixServer(socketURL: socketURL)
        addTeardownBlock { server.stop() }

        let client = AgentClient(
            socketURL: socketURL,
            deadline: AgentClientDeadline(milliseconds: 100)
        )
        let started = Date()

        XCTAssertThrowsError(
            try client.send(AgentRequest(command: "status", arguments: []))
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8)
    }

    func testProductionDeadlineIsFiniteAndAtMostTwoHundredMillisecondsPerPhase() {
        XCTAssertGreaterThan(AgentClientDeadline.production.milliseconds, 0)
        XCTAssertLessThanOrEqual(AgentClientDeadline.production.milliseconds, 200)
    }
}

private final class StalledUnixServer: @unchecked Sendable {
    private var descriptor: Int32
    private var clientDescriptor: Int32 = -1

    init(socketURL: URL) throws {
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let bindStatus = try withUnixAddress(path: socketURL.path) { address, length in
            Darwin.bind(descriptor, address, length)
        }
        guard bindStatus == 0, Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EIO)
        }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            clientDescriptor = Darwin.accept(descriptor, nil, nil)
        }
    }

    func stop() {
        if clientDescriptor >= 0 {
            Darwin.shutdown(clientDescriptor, SHUT_RDWR)
            Darwin.close(clientDescriptor)
            clientDescriptor = -1
        }
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit { stop() }
}
