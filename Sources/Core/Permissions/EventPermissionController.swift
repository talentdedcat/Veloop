import ApplicationServices
import Foundation

public struct EventPermissionStatus: Codable, Equatable, Sendable {
    public let listenEvents: Bool
    public let postEvents: Bool
    public let accessibility: Bool

    public init(listenEvents: Bool, postEvents: Bool, accessibility: Bool) {
        self.listenEvents = listenEvents
        self.postEvents = postEvents
        self.accessibility = accessibility
    }

    public var canCycle: Bool {
        listenEvents && postEvents && accessibility
    }
}

final class EventPermissionController {
    func status() -> EventPermissionStatus {
        EventPermissionStatus(
            listenEvents: CGPreflightListenEventAccess(),
            postEvents: CGPreflightPostEventAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    @discardableResult
    func request() -> EventPermissionStatus {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return status()
    }
}
