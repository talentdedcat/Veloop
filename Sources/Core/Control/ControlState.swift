import Foundation

public struct ControlState: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let historyCount: Int
    public let storageBytes: UInt64
    public let configuration: Configuration
    public let permissions: EventPermissionStatus

    public init(
        enabled: Bool,
        historyCount: Int,
        storageBytes: UInt64,
        configuration: Configuration,
        permissions: EventPermissionStatus
    ) {
        self.enabled = enabled
        self.historyCount = historyCount
        self.storageBytes = storageBytes
        self.configuration = configuration
        self.permissions = permissions
    }
}

public struct ControlUpdate: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var showContentPreviews: Bool?
    public var maximumHistoryCount: Int?
    public var maximumDiskBytes: UInt64?

    public init(
        enabled: Bool? = nil,
        showContentPreviews: Bool? = nil,
        maximumHistoryCount: Int? = nil,
        maximumDiskBytes: UInt64? = nil
    ) {
        self.enabled = enabled
        self.showContentPreviews = showContentPreviews
        self.maximumHistoryCount = maximumHistoryCount
        self.maximumDiskBytes = maximumDiskBytes
    }
}

public protocol AgentControlling: AnyObject, Sendable {
    func state() throws -> ControlState
    func update(_ update: ControlUpdate) throws -> ControlState
    func clearHistory() throws
    func requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus
}

public protocol AgentLifecycleControlling: AnyObject, Sendable {
    func ensureRegisteredAndRunning() throws
}
