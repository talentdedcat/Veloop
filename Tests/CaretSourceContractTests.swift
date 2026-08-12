import Foundation
import XCTest

final class CaretSourceContractTests: XCTestCase {
    func testCaretSubsystemUsesPaletteThenFocusedAccessibilityGeometry() throws {
        let source = try caretSource()

        for required in [
            "CFMessagePortCreateRemote",
            "CFMessagePortSendRequest",
            "paletteLineRectangle",
            "paletteRangeRectangle",
            "AXUIElementCreateApplication",
            "AXUIElementSetMessagingTimeout",
            "kAXFocusedUIElementAttribute",
            "AXUIElementGetPid",
            "kAXSelectedTextRangeAttribute",
            "kAXSelectedTextMarkerRangeAttribute",
            "kAXRoleAttribute",
            "kAXValueAttribute",
            "kAXPositionAttribute",
            "kAXSizeAttribute",
            "kAXBoundsForRangeParameterizedAttribute",
            "kAXBoundsForTextMarkerRangeParameterizedAttribute",
            "accessibilityFocusedElement",
            "accessibilityEmptyTextControl",
            "currentCaretLocation()",
        ] {
            XCTAssertTrue(source.contains(required), "missing caret contract: \(required)")
        }

        for forbidden in [
            "AXObserver",
            "kAXChildrenAttribute",
            "CGEvent",
            "mouseLocation",
            "mousePointer",
            "recentMouseClick",
            "lastClickLocation",
            "composedCharacter",
            "descendantTextElement",
            "controlFrameEstimate",
            "scheduleRetry",
            "pollInterval",
            "AXUIElementCreateSystemWide",
        ] {
            XCTAssertFalse(source.contains(forbidden), "broad caret fallback remains: \(forbidden)")
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

    func testAgentResolvesCaretOnlyWhenCycleStarts() throws {
        let runtime = try text("Sources/Core/Agent/VeloopAgentRuntime.swift")

        XCTAssertTrue(runtime.contains("caretLocator.currentCaretLocation()?.globalRect"))
        let placement = try XCTUnwrap(runtime.range(of: "placementSession.makePreparation()"))
        let preparationQueue = try XCTUnwrap(
            runtime.range(of: "cyclePreparationQueue.async", range: placement.lowerBound..<runtime.endIndex)
        )
        let invocation = try XCTUnwrap(
            runtime.range(of: "preparePlacement()", range: preparationQueue.lowerBound..<runtime.endIndex)
        )
        XCTAssertLessThan(placement.lowerBound, preparationQueue.lowerBound)
        XCTAssertLessThan(preparationQueue.lowerBound, invocation.lowerBound)
        let controllerStart = try XCTUnwrap(runtime.range(of: "let cycleController"))
        let preparationStart = try XCTUnwrap(
            runtime.range(of: "prepareCycle:", range: controllerStart.lowerBound..<runtime.endIndex)
        )
        let eventCallbackConfiguration = runtime[controllerStart.lowerBound..<preparationStart.lowerBound]
        XCTAssertFalse(eventCallbackConfiguration.contains("permissions?.status()"))
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
            "VeloopRegisterController",
            "VeloopUnregisterController",
            "VeloopActiveControllersForBundle",
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

    func testPaletteTriesEveryActiveContextForTheFrontmostApplication() throws {
        let source = try text("Sources/Palette/main.m")
        let handler = try bracedBody(after: "static CFDataRef VeloopHandleCaretRequest", in: source)

        XCTAssertTrue(handler.contains("VeloopActiveControllersForBundle(requestedBundle)"))
        XCTAssertTrue(handler.contains("for (VeloopPaletteController *controller in controllers)"))
        XCTAssertTrue(handler.contains("if (response != nil)"))
        XCTAssertFalse(handler.contains("[VeloopControllers objectForKey:requestedBundle]"))
    }

    func testPaletteCharacterAttributesCannotBlockCollapsedRangeCaretQuery() throws {
        let source = try text("Sources/Palette/main.m")
        let method = try bracedBody(after: "- (NSDictionary *)caretResponseForBundle:", in: source)
        let lineQuery = try XCTUnwrap(method.range(of: "attributesForCharacterIndex:"))
        let firstCatch = try XCTUnwrap(method.range(of: "@catch", range: lineQuery.upperBound..<method.endIndex))
        let rangeQuery = try XCTUnwrap(method.range(of: "firstRectForCharacterRange:"))

        XCTAssertLessThan(lineQuery.lowerBound, firstCatch.lowerBound)
        XCTAssertLessThan(firstCatch.lowerBound, rangeQuery.lowerBound)
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
        .filter {
            $0.pathExtension == "swift"
                && ($0.lastPathComponent.hasPrefix("Caret")
                    || $0.lastPathComponent == "FocusedAccessibilityCaretClient.swift")
        }
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

    private func bracedBody(after marker: String, in source: String) throws -> Substring {
        let markerRange = try XCTUnwrap(source.range(of: marker))
        let opening = try XCTUnwrap(source[markerRange.upperBound...].firstIndex(of: "{"))
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[opening...cursor]
                }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
