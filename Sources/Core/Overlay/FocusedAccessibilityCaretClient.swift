import ApplicationServices
import Foundation

protocol AccessibilityCaretQuerying: AnyObject {
    func query(target: CaretTarget) -> AccessibilityCaretQueryResult
}

final class FocusedAccessibilityCaretClient: AccessibilityCaretQuerying {
    private let isTrusted: () -> Bool
    private let readFocusedElement: () -> FocusedAccessibilityReadResult

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        readFocusedElement: @escaping () -> FocusedAccessibilityReadResult = {
            FocusedAccessibilityCaretClient.readSystemFocusedElement()
        }
    ) {
        self.isTrusted = isTrusted
        self.readFocusedElement = readFocusedElement
    }

    func query(target: CaretTarget) -> AccessibilityCaretQueryResult {
        guard isTrusted() else { return .failed(.untrusted) }
        guard case let .element(
            processIdentifier,
            textMarkerBounds,
            selectedRange,
            boundsForRange
        ) = readFocusedElement() else {
            return .failed(.missingFocusedElement)
        }
        guard processIdentifier == target.processIdentifier else {
            return .failed(.processMismatch)
        }
        if let textMarkerBounds, Self.isCaretShaped(textMarkerBounds) {
            return .located(textMarkerBounds)
        }
        guard let selectedRange else { return .failed(.missingSelection) }
        guard selectedRange.length == 0 else {
            return .failed(.selectionNotCollapsed)
        }
        guard let bounds = boundsForRange(selectedRange) else {
            return .failed(.missingBounds)
        }
        return .located(bounds)
    }

    private static func isCaretShaped(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.size.width.isFinite
            && bounds.size.height.isFinite
            && bounds.width >= 0
            && bounds.width <= 8
            && bounds.height >= 4
            && bounds.height <= 160
    }

    private static func readSystemFocusedElement() -> FocusedAccessibilityReadResult {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .missingFocusedElement
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var processIdentifier: pid_t = 0
        _ = AXUIElementGetPid(focused, &processIdentifier)

        var textMarkerBounds: CGRect?
        var markerRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextMarkerRangeAttribute as CFString,
            &markerRangeValue
        ) == .success,
        let markerRangeValue {
            var markerBoundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                focused,
                kAXBoundsForTextMarkerRangeParameterizedAttribute as CFString,
                markerRangeValue,
                &markerBoundsValue
            ) == .success,
            let markerBoundsValue,
            CFGetTypeID(markerBoundsValue) == AXValueGetTypeID() {
                let markerBoundsAXValue = unsafeBitCast(markerBoundsValue, to: AXValue.self)
                var decodedBounds = CGRect.zero
                if AXValueGetValue(markerBoundsAXValue, .cgRect, &decodedBounds) {
                    textMarkerBounds = decodedBounds
                }
            }
        }

        var selectedValue: CFTypeRef?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedValue
        ) == .success,
        let selectedValue,
        CFGetTypeID(selectedValue) == AXValueGetTypeID() {
            let selectedAXValue = unsafeBitCast(selectedValue, to: AXValue.self)
            var decodedRange = CFRange()
            if AXValueGetValue(selectedAXValue, .cfRange, &decodedRange) {
                selectedRange = decodedRange
            }
        }

        return .element(
            processIdentifier: processIdentifier,
            textMarkerBounds: textMarkerBounds,
            selectedRange: selectedRange,
            boundsForRange: { range in
                var mutableRange = range
                guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
                    return nil
                }
                var boundsValue: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(
                    focused,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    rangeValue,
                    &boundsValue
                ) == .success,
                let boundsValue,
                CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
                    return nil
                }
                let boundsAXValue = unsafeBitCast(boundsValue, to: AXValue.self)
                var bounds = CGRect.zero
                return AXValueGetValue(boundsAXValue, .cgRect, &bounds) ? bounds : nil
            }
        )
    }
}
