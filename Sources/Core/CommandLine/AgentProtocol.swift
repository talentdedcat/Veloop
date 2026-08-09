import Foundation

struct AgentRequest: Codable, Equatable {
    let command: String
    let arguments: [String]
}

struct AgentResponse: Codable, Equatable {
    let succeeded: Bool
    let output: String?
    let error: String?

    static func success(_ output: String) -> AgentResponse {
        AgentResponse(succeeded: true, output: output, error: nil)
    }

    static func failure(_ error: String) -> AgentResponse {
        AgentResponse(succeeded: false, output: nil, error: error)
    }
}

enum AgentProtocolError: Error, Equatable {
    case messageTooLarge
    case malformedMessage
}

enum AgentProtocolCodec {
    static let maximumMessageBytes = 65_536

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        guard data.count < maximumMessageBytes else {
            throw AgentProtocolError.messageTooLarge
        }
        data.append(0x0a)
        return data
    }

    static func decodeRequest(_ data: Data) throws -> AgentRequest {
        try decode(AgentRequest.self, from: data)
    }

    static func decodeResponse(_ data: Data) throws -> AgentResponse {
        try decode(AgentResponse.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumMessageBytes else {
            throw AgentProtocolError.messageTooLarge
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentProtocolError.malformedMessage
        }
    }
}
