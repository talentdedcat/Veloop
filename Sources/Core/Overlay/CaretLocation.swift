import CoreGraphics
import Foundation

public enum CaretSource: String, Sendable, Equatable, CaseIterable {
    case paletteLineRectangle
    case paletteRangeRectangle
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

struct PaletteScreenGeometry: Equatable, Sendable {
    let appKitFrame: CGRect
    let cgDisplayBounds: CGRect
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
        guard converted.origin.x.isFinite,
              converted.origin.y.isFinite,
              screen.cgDisplayBounds.insetBy(dx: -1, dy: -1).intersects(converted) else {
            return nil
        }
        return converted
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
