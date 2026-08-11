import ApplicationServices
import Foundation

public enum EventPermissionGroup: String, Codable, Equatable, Sendable {
    case inputMonitoring
    case accessibility
}

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

    public func isAllowed(for group: EventPermissionGroup) -> Bool {
        switch group {
        case .inputMonitoring:
            listenEvents
        case .accessibility:
            postEvents && accessibility
        }
    }
}

final class EventPermissionController {
    private let preflightListenEventAccess: () -> Bool
    private let preflightPostEventAccess: () -> Bool
    private let preflightAccessibility: () -> Bool

    init(
        preflightListenEventAccess: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        preflightPostEventAccess: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        preflightAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.preflightListenEventAccess = preflightListenEventAccess
        self.preflightPostEventAccess = preflightPostEventAccess
        self.preflightAccessibility = preflightAccessibility
    }

    func status() -> EventPermissionStatus {
        EventPermissionStatus(
            listenEvents: preflightListenEventAccess(),
            postEvents: preflightPostEventAccess(),
            accessibility: preflightAccessibility()
        )
    }

    @discardableResult
    func request(_ group: EventPermissionGroup) -> EventPermissionStatus {
        _ = group
        return status()
    }
}
