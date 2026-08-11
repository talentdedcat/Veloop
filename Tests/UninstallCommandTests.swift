import Foundation
import XCTest
@testable import VeloopCore

final class UninstallCommandTests: XCTestCase {
    func testExactPurgeCommandRunsLocalCleanupWithoutAgentIPC() {
        let requester = RejectingRequester()
        let cleanup = CleanupCallRecorder()
        let controller = CommandLineController(
            requester: requester,
            openDataDirectory: { false },
            uninstallPurge: cleanup.call
        )

        let result = controller.run(arguments: ["uninstall", "--purge"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertEqual(result.standardError, "")
        XCTAssertEqual(cleanup.callCount, 1)
        XCTAssertEqual(requester.callCount, 0)
    }

    func testAllOtherUninstallFormsReturnUsageWithoutCleanup() {
        let cleanup = CleanupCallRecorder()
        let controller = CommandLineController(
            requester: RejectingRequester(),
            openDataDirectory: { false },
            uninstallPurge: cleanup.call
        )

        for arguments in [["uninstall"], ["uninstall", "--keep"], ["uninstall", "--purge", "extra"]] {
            let result = controller.run(arguments: arguments)
            XCTAssertEqual(result.exitCode, 2, "\(arguments)")
            XCTAssertTrue(result.standardError.contains("uninstall --purge"))
        }
        XCTAssertEqual(cleanup.callCount, 0)
    }

    func testCleanupFailureReturnsNonzero() {
        let controller = CommandLineController(
            requester: RejectingRequester(),
            openDataDirectory: { false },
            uninstallPurge: { throw TestUninstallError.failed }
        )

        let result = controller.run(arguments: ["uninstall", "--purge"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.standardError, "Veloop could not be completely removed.\n")
    }

    func testCaskOrdinaryUninstallUsesPurgeScriptWithoutPrivilegedDeleteArtifact() throws {
        let cask = try repositoryText("Casks/veloop.rb")
        let uninstallStart = try XCTUnwrap(cask.range(of: "  uninstall "))
        let zapStart = try XCTUnwrap(
            cask.range(of: "\n  zap ", range: uninstallStart.lowerBound..<cask.endIndex)
        )
        let uninstall = String(cask[uninstallStart.lowerBound..<zapStart.lowerBound])

        XCTAssertTrue(uninstall.contains("executable:"))
        XCTAssertTrue(uninstall.contains(
            "\"#{appdir}/Veloop.app/Contents/Resources/veloopctl\""
        ))
        XCTAssertTrue(uninstall.contains("args:"))
        XCTAssertTrue(uninstall.contains("[\"uninstall\", \"--purge\"]"))
        XCTAssertTrue(uninstall.contains("must_succeed: true"))
        XCTAssertTrue(uninstall.contains("com.veloop.service"))
        XCTAssertTrue(uninstall.contains("com.veloop.uninstall-watcher"))
        XCTAssertFalse(uninstall.contains("delete:"))
        XCTAssertFalse(
            cask.contains("\"/Applications/Veloop Agent.app\""),
            "system Applications safety net must remain in veloopctl to avoid sudo"
        )
        XCTAssertTrue(
            try repositoryText("Sources/Core/Uninstall/VeloopCleanupPaths.swift")
                .contains("Veloop Agent.app")
        )
        for path in allSafetyNetPaths {
            XCTAssertTrue(cask.contains(path), "zap must retain user-path safety net \(path)")
        }
    }
}

private func repositoryText(_ path: String) throws -> String {
    try String(
        contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path),
        encoding: .utf8
    )
}

private let allSafetyNetPaths = [
    "~/Applications/Veloop Agent.app",
    "~/Library/Application Support/Veloop",
    "~/Library/Caches/com.veloop.app",
    "~/Library/Caches/com.veloop.diagnostics.carethost",
    "~/Library/Caches/com.veloop.service",
    "~/Library/Input Methods/VeloopPalette.app",
    "~/Library/LaunchAgents/com.veloop.service.plist",
    "~/Library/LaunchAgents/com.veloop.uninstall-watcher.plist",
    "~/Library/Preferences/com.veloop.app.plist",
    "~/Library/Preferences/com.veloop.service.plist",
    "~/Library/Preferences/com.veloop.shared.plist",
    "~/Library/Saved Application State/com.veloop.app.savedState",
    "~/Library/WebKit/com.veloop.diagnostics.carethost",
]

private enum TestUninstallError: Error {
    case failed
}

private final class RejectingRequester: AgentRequesting, @unchecked Sendable {
    private(set) var callCount = 0

    func send(_ request: AgentRequest) throws -> AgentResponse {
        callCount += 1
        throw TestUninstallError.failed
    }
}

private final class CleanupCallRecorder: @unchecked Sendable {
    private(set) var callCount = 0
    lazy var call: () throws -> Void = { [self] in callCount += 1 }
}
