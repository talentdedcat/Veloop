import Foundation

public enum AgentControlClientError: Error, Equatable {
    case requestFailed(String)
    case missingResponse
    case invalidResponse
}

public final class AgentControlClient: AgentControlling {
    private let requester: AgentRequesting

    public convenience init() throws {
        let paths = try StoragePaths.userDefault()
        self.init(socketURL: paths.socket)
    }

    public init(socketURL: URL) {
        self.requester = AgentClient(socketURL: socketURL)
    }

    init(requester: AgentRequesting) {
        self.requester = requester
    }

    public func state() throws -> ControlState {
        try decodeResponse(for: AgentRequest(command: "control-state", arguments: []))
    }

    public func update(_ update: ControlUpdate) throws -> ControlState {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let argument = String(decoding: try encoder.encode(update), as: UTF8.self)
        return try decodeResponse(for: AgentRequest(command: "control-update", arguments: [argument]))
    }

    public func clearHistory() throws {
        _ = try output(for: AgentRequest(command: "clear", arguments: []))
    }

    public func requestPermissions(_ group: EventPermissionGroup) throws -> EventPermissionStatus {
        try decodeResponse(for: AgentRequest(command: "request-permissions", arguments: [group.rawValue]))
    }

    public func restart() throws {
        _ = try output(for: AgentRequest(command: "restart", arguments: []))
    }

    private func decodeResponse<T: Decodable>(for request: AgentRequest) throws -> T {
        guard let output = try output(for: request) else {
            throw AgentControlClientError.missingResponse
        }
        guard let data = output.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw AgentControlClientError.invalidResponse
        }
        return decoded
    }

    private func output(for request: AgentRequest) throws -> String? {
        let response = try requester.send(request)
        guard response.succeeded else {
            throw AgentControlClientError.requestFailed(response.error ?? "unknown agent error")
        }
        return response.output
    }
}
