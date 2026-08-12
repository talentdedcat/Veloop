import CoreGraphics
import Foundation
import XCTest
@testable import VeloopCore

final class FocusedAccessibilityCaretClientTests: XCTestCase {
    func testReadsFocusedElementFromTargetApplicationProcess() {
        var requestedProcessIdentifier: pid_t?
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { processIdentifier in
                requestedProcessIdentifier = processIdentifier
                return .missingFocusedElement
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingFocusedElement))
        XCTAssertEqual(requestedProcessIdentifier, Self.target.processIdentifier)
    }

    func testCollapsedSelectionForTargetReturnsBounds() {
        var requestedRange: CFRange?
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 3, length: 0),
                    boundsForRange: { range in
                        requestedRange = range
                        return CGRect(x: 500, y: 300, width: 1, height: 18)
                    }
                )
            }
        )

        XCTAssertEqual(
            client.query(target: Self.target),
            .located(CGRect(x: 500, y: 300, width: 1, height: 18))
        )
        XCTAssertEqual(requestedRange?.location, 3)
        XCTAssertEqual(requestedRange?.length, 0)
    }

    func testUntrustedProcessDoesNotReadFocusedElement() {
        var reads = 0
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { false },
            readFocusedElement: { _ in
                reads += 1
                return .missingFocusedElement
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.untrusted))
        XCTAssertEqual(reads, 0)
    }

    func testMissingFocusedElementIsRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in .missingFocusedElement }
        )

        XCTAssertEqual(
            client.query(target: Self.target),
            .failed(.missingFocusedElement)
        )
    }

    func testFocusedElementFromAnotherProcessIsRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 99,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in CGRect(x: 10, y: 10, width: 1, height: 16) }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.processMismatch))
    }

    func testMissingSelectionIsRejectedWithoutReadingBounds() {
        var boundsReads = 0
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: nil,
                    selectedRange: nil,
                    boundsForRange: { _ in boundsReads += 1; return nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingSelection))
        XCTAssertEqual(boundsReads, 0)
    }

    func testNonCollapsedSelectionIsRejectedWithoutReadingBounds() {
        var boundsReads = 0
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 1, length: 2),
                    boundsForRange: { _ in boundsReads += 1; return nil }
                )
            }
        )

        XCTAssertEqual(
            client.query(target: Self.target),
            .failed(.selectionNotCollapsed)
        )
        XCTAssertEqual(boundsReads, 0)
    }

    func testNonCollapsedSelectionRejectsCaretShapedTextMarker() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    frame: CGRect(x: 100, y: 100, width: 300, height: 40),
                    textMarkerBounds: CGRect(x: 120, y: 110, width: 1, height: 18),
                    selectedRange: CFRange(location: 1, length: 2),
                    boundsForRange: { _ in nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.selectionNotCollapsed))
    }

    func testMissingBoundsIsRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 1, length: 0),
                    boundsForRange: { _ in nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingBounds))
    }

    func testCollapsedSelectionPrefersTextMarkerBounds() {
        var legacyBoundsReads = 0
        let markerBounds = CGRect(x: 420, y: 180, width: 0, height: 19)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: markerBounds,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in
                        legacyBoundsReads += 1
                        return CGRect(x: 1, y: 1, width: 1, height: 1)
                    }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .located(markerBounds))
        XCTAssertEqual(legacyBoundsReads, 0)
    }

    func testMissingTextMarkerBoundsFallsBackToLegacyRange() {
        let legacyBounds = CGRect(x: 500, y: 300, width: 1, height: 18)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 2, length: 0),
                    boundsForRange: { _ in legacyBounds }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .located(legacyBounds))
    }

    func testInvalidTextMarkerBoundsFallsBackToLegacyRange() {
        let legacyBounds = CGRect(x: 500, y: 300, width: 1, height: 18)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: .zero,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in legacyBounds }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .located(legacyBounds))
    }

    func testInvalidTextMarkerAndLegacyBoundsAreRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    textMarkerBounds: .zero,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in .zero }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingBounds))
    }

    func testValidTextMarkerInsideFocusedFrameRemainsPreferred() {
        let marker = CGRect(x: 120, y: 111, width: 0, height: 18)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    role: "AXTextField",
                    valueIsEmpty: true,
                    frame: CGRect(x: 100, y: 100, width: 300, height: 40),
                    textMarkerBounds: marker,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in XCTFail("legacy range should not be queried"); return nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .located(marker))
    }

    func testEmptyTextFieldFallsBackToCaretInsideFocusedFrame() throws {
        let frame = CGRect(x: 289, y: 212, width: 640, height: 53)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    role: "AXTextField",
                    valueIsEmpty: true,
                    frame: frame,
                    textMarkerBounds: CGRect(x: 209, y: 110, width: 1, height: 18),
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in CGRect(x: 209, y: 110, width: 1, height: 18) }
                )
            }
        )

        let bounds = try locatedBounds(client.query(target: Self.target))
        XCTAssertTrue(frame.contains(CGPoint(x: bounds.midX, y: bounds.midY)))
        XCTAssertLessThan(bounds.midX, frame.minX + frame.width / 4)
        XCTAssertEqual(bounds.width, 1)
        XCTAssertGreaterThanOrEqual(bounds.height, 14)
    }

    func testEmptyTextAreaFallbackUsesFirstLineNearTop() throws {
        let frame = CGRect(x: 289, y: 418, width: 670, height: 73)
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    role: "AXTextArea",
                    valueIsEmpty: true,
                    frame: frame,
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in nil }
                )
            }
        )

        let bounds = try locatedBounds(client.query(target: Self.target))
        XCTAssertLessThan(bounds.midY, frame.midY)
        XCTAssertGreaterThan(bounds.minY, frame.minY)
    }

    func testNonEmptyTextFieldDoesNotUseFocusedFrameFallback() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    role: "AXTextField",
                    valueIsEmpty: false,
                    frame: CGRect(x: 100, y: 100, width: 300, height: 40),
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 3, length: 0),
                    boundsForRange: { _ in nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingBounds))
    }

    func testNonTextElementDoesNotUseFocusedFrameFallback() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: { _ in
                .element(
                    processIdentifier: 42,
                    role: "AXButton",
                    valueIsEmpty: true,
                    frame: CGRect(x: 100, y: 100, width: 300, height: 40),
                    textMarkerBounds: nil,
                    selectedRange: CFRange(location: 0, length: 0),
                    boundsForRange: { _ in nil }
                )
            }
        )

        XCTAssertEqual(client.query(target: Self.target), .failed(.missingBounds))
    }

    private func locatedBounds(
        _ result: AccessibilityCaretQueryResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGRect {
        guard case let .located(bounds, _) = result else {
            XCTFail("expected located result, got \(result)", file: file, line: line)
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        return bounds
    }

    private static let target = CaretTarget(
        processIdentifier: 42,
        bundleIdentifier: "com.example.editor"
    )
}
