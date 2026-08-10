import Foundation
import XCTest
@testable import VeloopCore

final class AgentReadinessWaiterTests: XCTestCase {
    func testImmediateSuccessfulProbeReturnsWithoutWaiting() throws {
        let directory = try temporaryDirectory()
        let waiter = AgentReadinessWaiter(
            socketDirectoryURL: directory,
            timeoutMilliseconds: 500,
            probe: { true }
        )

        let started = Date()
        XCTAssertTrue(waiter.wait())
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.1)
    }

    func testDirectoryEventTriggersASecondProbe() throws {
        let directory = try temporaryDirectory()
        let readiness = ReadinessFlag()
        let waiter = AgentReadinessWaiter(
            socketDirectoryURL: directory,
            timeoutMilliseconds: 500,
            probe: { readiness.value }
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            readiness.value = true
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent("agent.sock").path,
                contents: Data()
            )
        }

        XCTAssertTrue(waiter.wait())
    }

    func testDeadlineReturnsFalseWithoutPolling() throws {
        let directory = try temporaryDirectory()
        let probes = ReadinessProbeCounter()
        let waiter = AgentReadinessWaiter(
            socketDirectoryURL: directory,
            timeoutMilliseconds: 100,
            probe: { probes.recordFalse() }
        )
        let started = Date()

        XCTAssertFalse(waiter.wait())
        XCTAssertEqual(probes.count, 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentReadinessWaiterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private final class ReadinessFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private final class ReadinessProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var count: Int { lock.withLock { storage } }
    func recordFalse() -> Bool {
        lock.withLock { storage += 1 }
        return false
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
