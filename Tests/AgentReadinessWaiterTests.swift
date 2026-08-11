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

    func testSecondProbeAfterWatcherRegistrationClosesCreationRace() throws {
        let directory = try temporaryDirectory()
        let readiness = ReadinessSequence([false, true])
        let waiter = AgentReadinessWaiter(
            socketDirectoryURL: directory,
            timeoutMilliseconds: 500,
            probe: { readiness.next() }
        )
        let started = Date()

        XCTAssertTrue(waiter.wait())
        XCTAssertEqual(readiness.count, 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.1)
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
        XCTAssertEqual(probes.count, 2)
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

private final class ReadinessSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool]
    private var storageCount = 0

    init(_ values: [Bool]) {
        self.values = values
    }

    var count: Int { lock.withLock { storageCount } }

    func next() -> Bool {
        lock.withLock {
            storageCount += 1
            return values.isEmpty ? false : values.removeFirst()
        }
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
