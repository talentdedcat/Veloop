import AppKit
import XCTest
@testable import VeloopCore

final class CaretLocatorTests: XCTestCase {
    func testPaletteLineRectangleBecomesCaretLocation() throws {
        let response = PaletteCaretResponse(
            appKitRect: CGRect(x: 320, y: 240, width: 1, height: 18),
            source: .paletteLineRectangle,
            processIdentifier: 42
        )
        let query = PaletteQueryStub(response: response)
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 700, y: 400, width: 1, height: 18)
        ))
        let locator = CaretLocator(
            query: query,
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 42, bundleIdentifier: "com.example.editor")
            },
            screensProvider: {
                [PaletteScreenGeometry(
                    appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    cgDisplayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
                )]
            }
        )

        let location = try XCTUnwrap(locator.currentCaretLocation())

        XCTAssertEqual(location.globalRect, CGRect(x: 320, y: 642, width: 1, height: 18))
        XCTAssertEqual(location.anchorPoint, CGPoint(x: 321, y: 660))
        XCTAssertEqual(location.processIdentifier, 42)
        XCTAssertEqual(location.applicationBundleIdentifier, "com.example.editor")
        XCTAssertEqual(location.source, .paletteLineRectangle)
        XCTAssertEqual(location.confidence, 1)
        XCTAssertFalse(location.isStale)
        XCTAssertEqual(query.requests, [CaretTarget(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor"
        )])
        XCTAssertTrue(accessibility.requests.isEmpty)
    }

    func testEachRequestQueriesTheCurrentTargetExactlyOnce() {
        let query = PaletteQueryStub(response: PaletteCaretResponse(
            appKitRect: CGRect(x: 100, y: 100, width: 1, height: 16),
            source: .paletteLineRectangle,
            processIdentifier: 1
        ))
        var target = CaretTarget(processIdentifier: 1, bundleIdentifier: "one")
        let locator = CaretLocator(
            query: query,
            targetProvider: { target },
            screensProvider: { [Self.screen] }
        )

        XCTAssertNotNil(locator.currentCaretLocation())
        target = CaretTarget(processIdentifier: 2, bundleIdentifier: "two")
        query.response = PaletteCaretResponse(
            appKitRect: CGRect(x: 100, y: 100, width: 1, height: 16),
            source: .paletteLineRectangle,
            processIdentifier: 2
        )
        XCTAssertNotNil(locator.currentCaretLocation())

        XCTAssertEqual(query.requests, [
            CaretTarget(processIdentifier: 1, bundleIdentifier: "one"),
            CaretTarget(processIdentifier: 2, bundleIdentifier: "two"),
        ])
    }

    func testMissingPaletteResponseUsesAccessibilityFailureStatus() {
        let query = PaletteQueryStub(response: nil)
        let accessibility = AccessibilityQueryStub(result: .failed(.missingFocusedElement))
        let locator = CaretLocator(
            query: query,
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.unsupported")
            },
            screensProvider: { [Self.screen] }
        )

        XCTAssertNil(locator.currentCaretLocation())
        XCTAssertEqual(
            locator.diagnosticReport().status,
            AccessibilityCaretFailure.missingFocusedElement.rawValue
        )
        XCTAssertEqual(query.requests.count, 1)
        XCTAssertEqual(accessibility.requests.count, 1)
    }

    func testMissingFrontmostBundleDoesNotQueryPalette() {
        let query = PaletteQueryStub(response: PaletteCaretResponse(
            appKitRect: CGRect(x: 1, y: 1, width: 1, height: 16),
            source: .paletteLineRectangle,
            processIdentifier: 1
        ))
        let locator = CaretLocator(
            query: query,
            targetProvider: { nil },
            screensProvider: { [Self.screen] }
        )

        XCTAssertNil(locator.currentCaretLocation())
        XCTAssertTrue(query.requests.isEmpty)
    }

    func testGeometryRejectsNonCaretRectangles() {
        for rect in [
            CGRect(x: CGFloat.nan, y: 100, width: 1, height: 16),
            CGRect.null,
            CGRect(x: 100, y: 100, width: 20, height: 16),
            CGRect(x: 100, y: 100, width: 1, height: 2),
            CGRect(x: 100, y: 100, width: 1, height: 240),
            CGRect(x: 5000, y: 5000, width: 1, height: 16),
            CGRect(x: 0, y: 0, width: 900, height: 600),
        ] {
            XCTAssertNil(PaletteCaretGeometry.cgCaretRect(
                fromAppKit: rect,
                screens: [Self.screen]
            ), "accepted invalid rect: \(rect)")
        }
    }

    func testGeometryAcceptsZeroWidthInsertionLine() {
        XCTAssertEqual(
            PaletteCaretGeometry.cgCaretRect(
                fromAppKit: CGRect(x: 240, y: 300, width: 0, height: 14),
                screens: [Self.screen]
            ),
            CGRect(x: 240, y: 586, width: 1, height: 14)
        )
    }

    func testGeometryUsesMatchingSecondaryDisplayCoordinateSpace() {
        let primary = PaletteScreenGeometry(
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            cgDisplayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let secondary = PaletteScreenGeometry(
            appKitFrame: CGRect(x: 1440, y: 100, width: 1920, height: 1080),
            cgDisplayBounds: CGRect(x: 1440, y: -280, width: 1920, height: 1080)
        )

        XCTAssertEqual(
            PaletteCaretGeometry.cgCaretRect(
                fromAppKit: CGRect(x: 1600, y: 500, width: 1, height: 20),
                screens: [primary, secondary]
            ),
            CGRect(x: 1600, y: 380, width: 1, height: 20)
        )
    }

    func testRangeRectangleUsesLowerConfidenceThanLineRectangle() throws {
        let query = PaletteQueryStub(response: PaletteCaretResponse(
            appKitRect: CGRect(x: 100, y: 100, width: 0, height: 16),
            source: .paletteRangeRectangle,
            processIdentifier: 8
        ))
        let locator = CaretLocator(
            query: query,
            targetProvider: { CaretTarget(processIdentifier: 8, bundleIdentifier: "editor") },
            screensProvider: { [Self.screen] }
        )

        let location = try XCTUnwrap(locator.currentCaretLocation())
        XCTAssertEqual(location.source, .paletteRangeRectangle)
        XCTAssertEqual(location.confidence, 0.95)
    }

    func testResponseForDifferentProcessFallsBackToAccessibility() throws {
        let query = PaletteQueryStub(response: PaletteCaretResponse(
            appKitRect: CGRect(x: 100, y: 100, width: 1, height: 16),
            source: .paletteLineRectangle,
            processIdentifier: 99
        ))
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 700, y: 400, width: 1, height: 18)
        ))
        let locator = CaretLocator(
            query: query,
            accessibilityQuery: accessibility,
            targetProvider: { CaretTarget(processIdentifier: 8, bundleIdentifier: "editor") },
            screensProvider: { [Self.screen] }
        )

        let location = try XCTUnwrap(locator.currentCaretLocation())
        XCTAssertEqual(location.source, .accessibilityFocusedElement)
        XCTAssertEqual(accessibility.requests.count, 1)
        XCTAssertEqual(locator.diagnosticReport().status, "located-accessibility")
    }

    func testMissingPaletteUsesFocusedAccessibilityCaret() throws {
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 700, y: 400, width: 1, height: 18)
        ))
        let locator = CaretLocator(
            query: PaletteQueryStub(response: nil),
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.editor")
            },
            screensProvider: { [Self.screen] }
        )

        let location = try XCTUnwrap(locator.currentCaretLocation())

        XCTAssertEqual(location.globalRect, CGRect(x: 700, y: 400, width: 1, height: 18))
        XCTAssertEqual(location.anchorPoint, CGPoint(x: 701, y: 418))
        XCTAssertEqual(location.processIdentifier, 7)
        XCTAssertEqual(location.applicationBundleIdentifier, "com.example.editor")
        XCTAssertEqual(location.source, .accessibilityFocusedElement)
        XCTAssertEqual(location.confidence, 0.9)
        XCTAssertFalse(location.isStale)
        XCTAssertEqual(accessibility.requests, [CaretTarget(
            processIdentifier: 7,
            bundleIdentifier: "com.example.editor"
        )])
        XCTAssertEqual(locator.diagnosticReport().status, "located-accessibility")
    }

    func testEstimatedEmptyControlCaretUsesDistinctSourceAndConfidence() throws {
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 220, y: 228, width: 1, height: 21),
            source: .accessibilityEmptyTextControl
        ))
        let locator = CaretLocator(
            query: PaletteQueryStub(response: nil),
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.browser")
            },
            screensProvider: { [Self.screen] }
        )

        let location = try XCTUnwrap(locator.currentCaretLocation())
        XCTAssertEqual(location.source, .accessibilityEmptyTextControl)
        XCTAssertEqual(location.confidence, 0.7)
        XCTAssertEqual(locator.diagnosticReport().status, "located-accessibility-empty-control")
    }

    func testInvalidPaletteGeometryFallsBackToAccessibility() throws {
        let query = PaletteQueryStub(response: PaletteCaretResponse(
            appKitRect: CGRect(x: 5_000, y: 5_000, width: 1, height: 16),
            source: .paletteLineRectangle,
            processIdentifier: 7
        ))
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 700, y: 400, width: 1, height: 18)
        ))
        let locator = CaretLocator(
            query: query,
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.editor")
            },
            screensProvider: { [Self.screen] }
        )

        XCTAssertEqual(
            try XCTUnwrap(locator.currentCaretLocation()).source,
            .accessibilityFocusedElement
        )
        XCTAssertEqual(accessibility.requests.count, 1)
    }

    func testInvalidAccessibilityGeometryReturnsNil() {
        let accessibility = AccessibilityQueryStub(result: .located(
            CGRect(x: 9_000, y: 9_000, width: 1, height: 18)
        ))
        let locator = CaretLocator(
            query: PaletteQueryStub(response: nil),
            accessibilityQuery: accessibility,
            targetProvider: {
                CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.editor")
            },
            screensProvider: { [Self.screen] }
        )

        XCTAssertNil(locator.currentCaretLocation())
        XCTAssertEqual(
            locator.diagnosticReport().status,
            "invalid-accessibility-geometry"
        )
    }

    func testAccessibilityFailuresBecomeExactDiagnosticStatuses() {
        for failure in [
            AccessibilityCaretFailure.untrusted,
            .missingFocusedElement,
            .processMismatch,
            .missingSelection,
            .selectionNotCollapsed,
            .missingBounds,
        ] {
            let locator = CaretLocator(
                query: PaletteQueryStub(response: nil),
                accessibilityQuery: AccessibilityQueryStub(result: .failed(failure)),
                targetProvider: {
                    CaretTarget(processIdentifier: 7, bundleIdentifier: "com.example.editor")
                },
                screensProvider: { [Self.screen] }
            )

            XCTAssertNil(locator.currentCaretLocation())
            XCTAssertEqual(locator.diagnosticReport().status, failure.rawValue)
        }
    }

    private static let screen = PaletteScreenGeometry(
        appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        cgDisplayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
    )
}

private final class PaletteQueryStub: PaletteCaretQuerying {
    var response: PaletteCaretResponse?
    private(set) var requests: [CaretTarget] = []

    init(response: PaletteCaretResponse?) {
        self.response = response
    }

    func query(target: CaretTarget) -> PaletteCaretResponse? {
        requests.append(target)
        return response
    }
}

private final class AccessibilityQueryStub: AccessibilityCaretQuerying {
    var result: AccessibilityCaretQueryResult
    private(set) var requests: [CaretTarget] = []

    init(result: AccessibilityCaretQueryResult) {
        self.result = result
    }

    func query(target: CaretTarget) -> AccessibilityCaretQueryResult {
        requests.append(target)
        return result
    }
}
