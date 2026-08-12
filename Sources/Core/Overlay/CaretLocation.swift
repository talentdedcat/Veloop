import CoreGraphics
import Foundation

public enum CaretSource: String, Sendable, Equatable, CaseIterable {
    case paletteLineRectangle
    case paletteRangeRectangle
    case accessibilityFocusedElement
}

public struct CaretLocation: Sendable, Equatable {
    public let globalRect: CGRect
    public let anchorPoint: CGPoint
    public let processIdentifier: pid_t
    public let applicationBundleIdentifier: String?
    public let source: CaretSource
    public let confidence: Double
    public let isStale: Bool

    public init(
        globalRect: CGRect,
        anchorPoint: CGPoint,
        processIdentifier: pid_t,
        applicationBundleIdentifier: String?,
        source: CaretSource,
        confidence: Double,
        isStale: Bool
    ) {
        self.globalRect = globalRect
        self.anchorPoint = anchorPoint
        self.processIdentifier = processIdentifier
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.source = source
        self.confidence = confidence
        self.isStale = isStale
    }
}

struct CaretTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
}

struct PaletteCaretResponse: Equatable, Sendable {
    let appKitRect: CGRect
    let source: CaretSource
    let processIdentifier: pid_t
}

enum AccessibilityCaretFailure: String, Equatable, Sendable {
    case untrusted = "accessibility-untrusted"
    case missingFocusedElement = "accessibility-no-focused-element"
    case processMismatch = "accessibility-process-mismatch"
    case missingSelection = "accessibility-no-selection"
    case selectionNotCollapsed = "accessibility-selection-not-collapsed"
    case missingBounds = "accessibility-no-bounds"
}

enum AccessibilityCaretQueryResult: Equatable, Sendable {
    case located(CGRect)
    case failed(AccessibilityCaretFailure)
}

enum FocusedAccessibilityReadResult {
    case element(
        processIdentifier: pid_t,
        textMarkerBounds: CGRect?,
        selectedRange: CFRange?,
        boundsForRange: (CFRange) -> CGRect?
    )
    case missingFocusedElement
}

struct PaletteScreenGeometry: Equatable, Sendable {
    let appKitFrame: CGRect
    let cgDisplayBounds: CGRect
}

enum GlobalCaretGeometry {
    private static let maximumCaretWidth: CGFloat = 8
    private static let minimumCaretHeight: CGFloat = 4
    private static let maximumCaretHeight: CGFloat = 160

    static func validated(_ rect: CGRect, displayBounds: [CGRect]) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite,
              rect.width >= 0,
              rect.width <= maximumCaretWidth,
              rect.height >= minimumCaretHeight,
              rect.height <= maximumCaretHeight else {
            return nil
        }
        let normalized = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width, 1),
            height: rect.height
        )
        guard displayBounds.contains(where: {
            $0.insetBy(dx: -1, dy: -1).intersects(normalized)
        }) else {
            return nil
        }
        return normalized
    }
}

enum PaletteCaretGeometry {
    private static let maximumCaretWidth: CGFloat = 8
    private static let minimumCaretHeight: CGFloat = 4
    private static let maximumCaretHeight: CGFloat = 160

    static func cgCaretRect(
        fromAppKit rect: CGRect,
        screens: [PaletteScreenGeometry]
    ) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite,
              rect.width >= 0,
              rect.width <= maximumCaretWidth,
              rect.height >= minimumCaretHeight,
              rect.height <= maximumCaretHeight else {
            return nil
        }

        let probe = CGPoint(x: rect.midX, y: rect.midY)
        guard let screen = screens.first(where: {
            $0.appKitFrame.insetBy(dx: -1, dy: -1).contains(probe)
        }) else {
            return nil
        }

        let normalizedWidth = max(1, rect.width)
        let converted = CGRect(
            x: screen.cgDisplayBounds.minX + rect.minX - screen.appKitFrame.minX,
            y: screen.cgDisplayBounds.minY + screen.appKitFrame.maxY - rect.maxY,
            width: normalizedWidth,
            height: rect.height
        )
        return GlobalCaretGeometry.validated(
            converted,
            displayBounds: screens.map(\.cgDisplayBounds)
        )
    }
}

struct CaretDiagnosticReport: Codable, Equatable, Sendable {
    let status: String
    let processIdentifier: pid_t?
    let source: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let confidence: Double?
}

final class CaretDiagnosticState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = "not-queried"
    private var processIdentifier: pid_t?
    private var location: CaretLocation?

    func record(status: String, processIdentifier: pid_t?, location: CaretLocation?) {
        lock.lock()
        self.status = status
        self.processIdentifier = processIdentifier
        self.location = location
        lock.unlock()
    }

    func report() -> CaretDiagnosticReport {
        lock.lock()
        let status = status
        let processIdentifier = location?.processIdentifier ?? processIdentifier
        let location = location
        lock.unlock()
        return CaretDiagnosticReport(
            status: status,
            processIdentifier: processIdentifier,
            source: location?.source.rawValue,
            x: location.map { Double($0.globalRect.minX) },
            y: location.map { Double($0.globalRect.minY) },
            width: location.map { Double($0.globalRect.width) },
            height: location.map { Double($0.globalRect.height) },
            confidence: location?.confidence
        )
    }
}
