import CoreGraphics

enum GlobalInputNormalizer {
    static func normalize(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> GlobalInputEvent {
        switch type {
        case .keyDown where keyCode == AppConstants.vKeyCode && flags.contains(.maskCommand):
            return .commandV
        case .keyUp where keyCode == AppConstants.vKeyCode:
            return .vKeyUp
        case .keyDown where keyCode == AppConstants.downArrowKeyCode:
            return .move(.newer)
        case .keyDown where keyCode == AppConstants.upArrowKeyCode:
            return .move(.older)
        case .keyUp where keyCode == AppConstants.downArrowKeyCode || keyCode == AppConstants.upArrowKeyCode:
            return .navigationKeyUp
        case .keyDown where keyCode == AppConstants.escapeKeyCode:
            return .escape
        case .flagsChanged where !flags.contains(.maskCommand):
            return .commandReleased
        default:
            return .other
        }
    }
}
