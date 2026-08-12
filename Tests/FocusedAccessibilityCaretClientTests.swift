import CoreGraphics
import Foundation
import XCTest
@testable import VeloopCore

final class FocusedAccessibilityCaretClientTests: XCTestCase {
    func testCollapsedSelectionForTargetReturnsBounds() {
        var requestedRange: CFRange?
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: {
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
            readFocusedElement: {
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
            readFocusedElement: { .missingFocusedElement }
        )

        XCTAssertEqual(
            client.query(target: Self.target),
            .failed(.missingFocusedElement)
        )
    }

    func testFocusedElementFromAnotherProcessIsRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: {
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
            readFocusedElement: {
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
            readFocusedElement: {
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

    func testMissingBoundsIsRejected() {
        let client = FocusedAccessibilityCaretClient(
            isTrusted: { true },
            readFocusedElement: {
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
            readFocusedElement: {
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
            readFocusedElement: {
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
            readFocusedElement: {
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

    private static let target = CaretTarget(
        processIdentifier: 42,
        bundleIdentifier: "com.example.editor"
    )
}
