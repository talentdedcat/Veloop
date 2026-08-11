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
            selectedRange,
            boundsForRange
        ) = readFocusedElement() else {
            return .failed(.missingFocusedElement)
        }
        guard processIdentifier == target.processIdentifier else {
            return .failed(.processMismatch)
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
