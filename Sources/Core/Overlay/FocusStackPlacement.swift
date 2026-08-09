import AppKit
import CoreGraphics

struct FocusStackScreenGeometry: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect
    let displayBounds: CGRect

    init(frame: NSRect, visibleFrame: NSRect, displayBounds: CGRect? = nil) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.displayBounds = displayBounds ?? frame
    }
}

final class FocusStackPlacementSession {
    private let lock = NSLock()
    private let resolve: () -> NSRect?
    private var preparedFrame: NSRect?

    init(resolve: @escaping () -> NSRect?) {
        self.resolve = resolve
    }

    func prepare() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if preparedFrame != nil {
            return true
        }
        preparedFrame = resolve()
        return preparedFrame != nil
    }

    func frame() -> NSRect? {
        lock.lock()
        defer { lock.unlock() }
        return preparedFrame
    }

    func reset() {
        lock.lock()
        preparedFrame = nil
        lock.unlock()
    }
}

final class FocusStackPlacementResolver {
    private static let spacing: CGFloat = 12
    private let caretBounds: () -> CGRect?

    init(caretBounds: @escaping () -> CGRect?) {
        self.caretBounds = caretBounds
    }

    func frame(panelSize: NSSize) -> NSRect? {
        Self.resolve(
            panelSize: panelSize,
            caretBoundsInCGCoordinates: caretBounds(),
            screens: NSScreen.screens.map { screen in
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                let displayBounds = number.map { CGDisplayBounds(CGDirectDisplayID($0.uint32Value)) }
                return FocusStackScreenGeometry(
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    displayBounds: displayBounds
                )
            }
        )
    }

    static func resolve(
        panelSize: NSSize,
        caretBoundsInCGCoordinates: CGRect?,
        screens: [FocusStackScreenGeometry]
    ) -> NSRect? {
        guard let caretBoundsInCGCoordinates,
              caretBoundsInCGCoordinates.origin.x.isFinite,
              caretBoundsInCGCoordinates.origin.y.isFinite,
              caretBoundsInCGCoordinates.width.isFinite,
              caretBoundsInCGCoordinates.height.isFinite,
              let screen = screens.first(where: {
                  $0.displayBounds.intersects(caretBoundsInCGCoordinates)
              }) else {
            return nil
        }
        guard panelSize.width <= screen.visibleFrame.width,
              panelSize.height <= screen.visibleFrame.height else {
            return nil
        }
        let caret = NSRect(
            x: screen.frame.minX + caretBoundsInCGCoordinates.minX - screen.displayBounds.minX,
            y: screen.frame.maxY - caretBoundsInCGCoordinates.maxY + screen.displayBounds.minY,
            width: max(caretBoundsInCGCoordinates.width, 1),
            height: max(caretBoundsInCGCoordinates.height, 1)
        )
        let desiredX = caret.maxX + Self.spacing
        let x = round(min(
            max(desiredX, screen.visibleFrame.minX),
            screen.visibleFrame.maxX - panelSize.width
        ))
        let lowerRight = NSRect(
            x: x,
            y: round(caret.minY - Self.spacing - panelSize.height),
            width: panelSize.width,
            height: panelSize.height
        )
        if screen.visibleFrame.contains(lowerRight) {
            return lowerRight
        }
        let upperRight = NSRect(
            x: x,
            y: round(caret.maxY + Self.spacing),
            width: panelSize.width,
            height: panelSize.height
        )
        return screen.visibleFrame.contains(upperRight) ? upperRight : nil
    }

}
