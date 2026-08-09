import Foundation
import XCTest

final class CaretSourceContractTests: XCTestCase {
    func testCaretSubsystemUsesOnlyPaletteGeometry() throws {
        let source = try caretSource()

        for required in [
            "CFMessagePortCreateRemote",
            "CFMessagePortSendRequest",
            "paletteLineRectangle",
            "paletteRangeRectangle",
            "currentCaretLocation()",
        ] {
            XCTAssertTrue(source.contains(required), "missing Palette contract: \(required)")
        }

        for forbidden in [
            "ApplicationServices",
            "AXUIElement",
            "AXObserver",
            "kAX",
            "CGEvent",
            "mouseLocation",
            "mousePointer",
            "recentMouseClick",
            "lastClickLocation",
            "composedCharacter",
            "textMarker",
            "descendantTextElement",
            "controlFrameEstimate",
            "scheduleRetry",
            "pollInterval",
            "bundleIdentifier ==",
            "bundleIdentifier !=",
        ] {
            XCTAssertFalse(source.contains(forbidden), "obsolete caret path remains: \(forbidden)")
        }
    }

    func testObsoleteCaretFilesAreRemoved() {
        for path in [
            "Sources/Core/Overlay/CaretAccessibilityBackend.swift",
            "Sources/Core/Overlay/CaretAXObserverHost.swift",
            "Sources/Core/Overlay/CaretInputEventMonitor.swift",
        ] {
            XCTAssertFalse(exists(path), "obsolete source still exists: \(path)")
        }
    }

    func testAgentQueriesPaletteOnlyWhenCycleStarts() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertTrue(runtime.contains("caretLocator.currentCaretLocation()?.globalRect"))
        XCTAssertFalse(runtime.contains("caretLifecycleTask"))
        XCTAssertFalse(runtime.contains("caretLocator.start()"))
        XCTAssertFalse(runtime.contains("caretLocator.stop()"))
        XCTAssertFalse(runtime.contains("invalidateForTextMutation"))
    }

    func testPaletteHelperDoesNotConsumeKeyboardInput() throws {
        let source = try text("Sources/Palette/main.m")

        for required in [
            "IMKInputController",
            "selectedRange",
            "attributesForCharacterIndex",
            "lineHeightRectangle",
            "firstRectForCharacterRange",
            "CFMessagePortCreateLocal",
            "DISPATCH_SOURCE_TYPE_VNODE",
            "VeloopRemoveInstalledState",
            "isActive",
            "removeObjectForKey:clientBundle",
            "dispatch_queue_create",
        ] {
            XCTAssertTrue(source.contains(required), "missing helper behavior: \(required)")
        }
        for forbidden in [
            "inputText:",
            "handleEvent:",
            "didCommandBySelector:",
            "bundleIdentifier isEqualToString",
            "AXUIElement",
            "CGEvent",
            "DISPATCH_SOURCE_TYPE_TIMER",
            "dispatch_get_global_queue",
        ] {
            XCTAssertFalse(source.contains(forbidden), "helper must stay additive: \(forbidden)")
        }
    }

    func testPaletteIPCValidatesIdentityAndBoundsPayloads() throws {
        let helper = try text("Sources/Palette/main.m")
        let client = try text("Sources/Core/Overlay/CaretLocator.swift")

        for required in [
            "VeloopMaximumMessageBytes = 4096",
            "CFDataGetLength(data)",
            "frontmostApplication",
            "processIdentifier",
            "requestedProcessIdentifier",
        ] {
            XCTAssertTrue(helper.contains(required), "missing Palette IPC guard: \(required)")
        }
        XCTAssertTrue(client.contains("maximumMessageBytes = 4_096"))
        XCTAssertTrue(client.contains("responseData.count <= Self.maximumMessageBytes"))
        XCTAssertTrue(client.contains("responseProcessIdentifier == target.processIdentifier"))
    }

    func testPaletteSelfCleanupIsNarrowlyScoped() throws {
        let source = try text("Sources/Palette/main.m")

        XCTAssertTrue(source.contains("VeloopHostMarkerPath()"))
        XCTAssertTrue(source.contains("Library/Input Methods/VeloopPalette.app"))
        XCTAssertTrue(source.contains("Library/LaunchAgents/com.veloop.service.plist"))
        for forbidden in [
            "VeloopSupportPath(),",
            "Library/Caches/com.veloop.app",
            "Library/Saved Application State/com.veloop.app.savedState",
            "Library/Preferences/com.veloop.app.plist",
            "Library/Preferences/com.veloop.service.plist",
        ] {
            XCTAssertFalse(source.contains(forbidden), "cleanup exceeds helper ownership: \(forbidden)")
        }
    }

    func testAgentExposesGeometryOnlyCaretDiagnosticCommand() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")
        XCTAssertTrue(runtime.contains("case \"caret-diagnostic\":"))
        XCTAssertTrue(runtime.contains("caretLocator.diagnosticReport()"))
    }

    private func caretSource() throws -> String {
        let overlay = repositoryRoot.appendingPathComponent("Sources/Core/Overlay", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(
            at: overlay,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" && $0.lastPathComponent.hasPrefix("Caret") }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
