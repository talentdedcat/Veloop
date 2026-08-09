import CoreGraphics
import Foundation

struct PasteEventInjector {
    @discardableResult
    func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: AppConstants.vKeyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: AppConstants.vKeyCode,
                  keyDown: false
              ) else {
            return false
        }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: AppConstants.syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
