import CoreGraphics
import Foundation

enum AppConstants {
    static let version = "0.2.2"
    static let bundleIdentifier = "com.veloop.app"
    static let agentLaunchAgentLabel = "com.veloop.service"
    static let uninstallWatcherLabel = "com.veloop.uninstall-watcher"
    static let syntheticEventMarker: Int64 = 0x5645_4c4f_4f50
    static let vKeyCode: CGKeyCode = 9
    static let downArrowKeyCode: CGKeyCode = 125
    static let upArrowKeyCode: CGKeyCode = 126
    static let escapeKeyCode: CGKeyCode = 53
}
