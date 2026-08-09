import Darwin
import Foundation

protocol AgentRequesting: AnyObject, Sendable {
    func send(_ request: AgentRequest) throws -> AgentResponse
}

enum AgentClientError: Error, Equatable {
    case agentUnavailable
    case communicationFailed
}

final class AgentClient: AgentRequesting {
    private let socketURL: URL

    init(socketURL: URL) {
        self.socketURL = socketURL
    }

    func send(_ request: AgentRequest) throws -> AgentResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentClientError.agentUnavailable
        }
        defer { Darwin.close(descriptor) }
        var noPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))

        do {
            let result = try withUnixAddress(path: socketURL.path) { address, length in
                Darwin.connect(descriptor, address, length)
            }
            guard result == 0 else {
                throw AgentClientError.agentUnavailable
            }
            try writeMessage(AgentProtocolCodec.encode(request), to: descriptor)
            return try AgentProtocolCodec.decodeResponse(readMessage(from: descriptor))
        } catch let error as AgentClientError {
            throw error
        } catch {
            throw AgentClientError.communicationFailed
        }
    }
}
