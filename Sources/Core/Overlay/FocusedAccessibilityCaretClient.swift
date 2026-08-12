import ApplicationServices
import Foundation

protocol AccessibilityCaretQuerying: AnyObject {
    func query(target: CaretTarget) -> AccessibilityCaretQueryResult
}

final class FocusedAccessibilityCaretClient: AccessibilityCaretQuerying {
    private let isTrusted: () -> Bool
    private let readFocusedElement: (pid_t) -> FocusedAccessibilityReadResult

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        readFocusedElement: @escaping (pid_t) -> FocusedAccessibilityReadResult = {
            FocusedAccessibilityCaretClient.readFocusedElement(processIdentifier: $0)
        }
    ) {
        self.isTrusted = isTrusted
        self.readFocusedElement = readFocusedElement
    }

    func query(target: CaretTarget) -> AccessibilityCaretQueryResult {
        guard isTrusted() else { return .failed(.untrusted) }
        guard case let .element(
            processIdentifier,
            role,
            valueIsEmpty,
            frame,
            textMarkerBounds,
            selectedRange,
            boundsForRange
        ) = readFocusedElement(target.processIdentifier) else {
            return .failed(.missingFocusedElement)
        }
        guard processIdentifier == target.processIdentifier else {
            return .failed(.processMismatch)
        }
        if let selectedRange, selectedRange.length != 0 {
            return .failed(.selectionNotCollapsed)
        }

        if let textMarkerBounds,
           Self.isUsableCaret(textMarkerBounds, inside: frame) {
            return .located(textMarkerBounds, focusedElementFrame: frame)
        }
        guard let selectedRange else { return .failed(.missingSelection) }
        if let bounds = boundsForRange(selectedRange),
           Self.isUsableCaret(bounds, inside: frame) {
            return .located(bounds, focusedElementFrame: frame)
        }
        if let estimatedBounds = Self.emptyTextControlCaret(
            role: role,
            valueIsEmpty: valueIsEmpty,
            selectedRange: selectedRange,
            frame: frame
        ) {
            return .located(
                estimatedBounds,
                source: .accessibilityEmptyTextControl,
                focusedElementFrame: frame
            )
        }
        return .failed(.missingBounds)
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

    private static func isUsableCaret(_ bounds: CGRect, inside frame: CGRect?) -> Bool {
        guard isCaretShaped(bounds) else { return false }
        guard let frame else { return true }
        guard isUsableControlFrame(frame) else { return false }
        let normalized = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 1),
            height: bounds.height
        )
        return frame.insetBy(dx: -1, dy: -1).contains(
            CGPoint(x: normalized.midX, y: normalized.midY)
        )
    }

    private static func emptyTextControlCaret(
        role: String?,
        valueIsEmpty: Bool?,
        selectedRange: CFRange,
        frame: CGRect?
    ) -> CGRect? {
        guard valueIsEmpty == true,
              selectedRange.location == 0,
              let role,
              role == kAXTextFieldRole as String || role == kAXTextAreaRole as String,
              let frame,
              isUsableControlFrame(frame) else {
            return nil
        }

        let inset = min(max(frame.height * 0.2, 6), 14)
        let height = min(max(frame.height * 0.4, 14), 24)
        let y = role == kAXTextAreaRole as String
            ? frame.minY + inset
            : frame.midY - height / 2
        return CGRect(
            x: frame.minX + inset,
            y: y,
            width: 1,
            height: height
        )
    }

    private static func isUsableControlFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.width >= 8
            && frame.height >= 8
    }

    private static func readFocusedElement(
        processIdentifier: pid_t
    ) -> FocusedAccessibilityReadResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
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

        var roleValue: CFTypeRef?
        let role: String? = if AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success {
            roleValue as? String
        } else {
            nil
        }

        var value: CFTypeRef?
        let valueIsEmpty: Bool? = if AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let text = value as? String {
            text.isEmpty
        } else {
            nil
        }

        var position: CGPoint?
        var positionValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focused,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        let positionValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID() {
            let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
            var decodedPosition = CGPoint.zero
            if AXValueGetValue(positionAXValue, .cgPoint, &decodedPosition) {
                position = decodedPosition
            }
        }

        var size: CGSize?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focused,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let sizeValue,
        CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
            var decodedSize = CGSize.zero
            if AXValueGetValue(sizeAXValue, .cgSize, &decodedSize) {
                size = decodedSize
            }
        }
        let frame = position.flatMap { position in
            size.map { CGRect(origin: position, size: $0) }
        }

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
            role: role,
            valueIsEmpty: valueIsEmpty,
            frame: frame,
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
