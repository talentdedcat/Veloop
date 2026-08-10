import Foundation
import XCTest
@testable import VeloopCore

final class TCCPermissionResetterTests: XCTestCase {
    func testResetUsesOnlyExactVeloopServicesAndBundleIdentifiers() throws {
        let recorder = CommandRecorder()
        let resetter = TCCPermissionResetter { executable, arguments in
            recorder.append(executable: executable, arguments: arguments)
            return 0
        }

        try resetter.resetVeloopPermissions()

        XCTAssertEqual(recorder.executables, Array(repeating: "/usr/bin/tccutil", count: 4))
        XCTAssertEqual(recorder.arguments, [
            ["reset", "ListenEvent", "com.veloop.app"],
            ["reset", "Accessibility", "com.veloop.app"],
            ["reset", "ListenEvent", "com.veloop.service"],
            ["reset", "Accessibility", "com.veloop.service"],
        ])
    }

    func testResetStopsAtFirstFailedCommand() {
        let recorder = CommandRecorder()
        let resetter = TCCPermissionResetter { executable, arguments in
            recorder.append(executable: executable, arguments: arguments)
            return recorder.arguments.count == 2 ? 1 : 0
        }

        XCTAssertThrowsError(try resetter.resetVeloopPermissions())
        XCTAssertEqual(recorder.arguments, [
            ["reset", "ListenEvent", "com.veloop.app"],
            ["reset", "Accessibility", "com.veloop.app"],
        ])
    }
}

private final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var executables: [String] = []
    private(set) var arguments: [[String]] = []

    func append(executable: URL, arguments: [String]) {
        lock.lock()
        executables.append(executable.path)
        self.arguments.append(arguments)
        lock.unlock()
    }
}
