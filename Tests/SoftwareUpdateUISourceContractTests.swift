import Foundation
import XCTest

final class SoftwareUpdateUISourceContractTests: XCTestCase {
    func testSettingsHasIndependentSoftwareUpdateSection() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let english = try text("Sources/App/en.lproj/Localizable.strings")
        let chinese = try text("Sources/App/zh-Hans.lproj/Localizable.strings")

        for symbol in [
            "softwareUpdateTitle",
            "softwareUpdateVersionLabel",
            "softwareUpdateStatusLabel",
            "checkForUpdatesButton",
            "updateCoordinator.checkManually()",
        ] {
            XCTAssertTrue(controller.contains(symbol), "Missing \(symbol)")
        }
        for key in [
            "update.section.title",
            "update.currentVersion",
            "update.check",
            "update.status.idle",
            "update.status.checking",
            "update.status.upToDate",
            "update.status.available",
            "update.status.failed",
            "update.window.title",
            "update.window.heading",
            "update.action.skip",
            "update.action.remindLater",
            "update.action.download",
            "update.error.openDownload",
        ] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), "English is missing \(key)")
            XCTAssertTrue(chinese.contains("\"\(key)\" = "), "Chinese is missing \(key)")
        }
    }

    func testUpdateWindowExposesExactlyThreeApprovedActions() throws {
        let window = try text("Sources/App/UpdateWindowController.swift")

        XCTAssertTrue(window.contains("case skip"))
        XCTAssertTrue(window.contains("case remindLater"))
        XCTAssertTrue(window.contains("case download"))
        XCTAssertEqual(window.components(separatedBy: "NSButton(").count - 1, 3)
        XCTAssertTrue(window.contains("update.action.skip"))
        XCTAssertTrue(window.contains("update.action.remindLater"))
        XCTAssertTrue(window.contains("update.action.download"))
    }

    func testAutomaticCheckStartsOnlyAfterControlWindowIsShown() throws {
        let delegate = try text("Sources/App/AppDelegate.swift")
        let launch = try functionBody(named: "applicationDidFinishLaunching", in: delegate)
        let showWindow = try XCTUnwrap(launch.range(of: "controller.showWindow(nil)"))
        let updateCheck = try XCTUnwrap(launch.range(of: "updateCoordinator.checkAutomatically()"))

        XCTAssertLessThan(showWindow.lowerBound, updateCheck.lowerBound)
        XCTAssertFalse(launch.contains("await updateCoordinator.checkAutomatically"))
    }

    func testManualCheckSupersedesAnOverlappingAutomaticPresentation() throws {
        let coordinator = try text("Sources/App/UpdateCoordinator.swift")

        XCTAssertTrue(coordinator.contains("checkRevision &+= 1"))
        XCTAssertTrue(coordinator.contains("guard revision == checkRevision else { return }"))
        XCTAssertTrue(coordinator.contains("runCheck(.automatic"))
        XCTAssertTrue(coordinator.contains("runCheck(.manual"))
    }

    func testUpdateCodeDoesNotEnterInputOrAgentSources() throws {
        let root = repositoryRoot.appendingPathComponent("Sources/Core")
        for directory in ["Input", "Clipboard", "Overlay", "Agent"] {
            let source = try allSwiftSource(in: root.appendingPathComponent(directory))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("updatechecker"), directory)
            XCTAssertFalse(source.contains("UpdateCoordinator"), directory)
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func allSwiftSource(in directory: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private func functionBody(named name: String, in source: String) throws -> Substring {
        let marker = try XCTUnwrap(source.range(of: "func \(name)"))
        let open = try XCTUnwrap(source[marker.upperBound...].firstIndex(of: "{"))
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return source[open...index] }
            }
            index = source.index(after: index)
        }
        throw SourceError.unbalanced
    }
}

private enum SourceError: Error {
    case unbalanced
}
