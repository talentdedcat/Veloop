import Darwin
import Foundation

protocol AgentRequesting: AnyObject, Sendable {
    func send(_ request: AgentRequest) throws -> AgentResponse
}

enum AgentClientError: Error, Equatable {
    case agentUnavailable
    case communicationFailed
}

struct AgentClientDeadline: Equatable, Sendable {
    static let production = AgentClientDeadline(milliseconds: 200)

    let milliseconds: Int32

    init(milliseconds: Int32) {
        self.milliseconds = max(1, milliseconds)
    }
}

final class AgentClient: AgentRequesting {
    private let socketURL: URL
    private let deadline: AgentClientDeadline

    init(
        socketURL: URL,
        deadline: AgentClientDeadline = .production
    ) {
        self.socketURL = socketURL
        self.deadline = deadline
    }

    func send(_ request: AgentRequest) throws -> AgentResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentClientError.agentUnavailable
        }
        defer { Darwin.close(descriptor) }
        var noPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        try configureIOTimeouts(descriptor)

        do {
            try connect(descriptor)
            try writeMessage(AgentProtocolCodec.encode(request), to: descriptor)
            return try AgentProtocolCodec.decodeResponse(readMessage(from: descriptor))
        } catch let error as AgentClientError {
            throw error
        } catch {
            throw AgentClientError.communicationFailed
        }
    }

    private func connect(_ descriptor: Int32) throws {
        let originalFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            throw AgentClientError.agentUnavailable
        }
        defer { _ = Darwin.fcntl(descriptor, F_SETFL, originalFlags) }

        let result = try withUnixAddress(path: socketURL.path) { address, length in
            Darwin.connect(descriptor, address, length)
        }
        if result == 0 { return }
        guard errno == EINPROGRESS else {
            throw AgentClientError.agentUnavailable
        }

        var descriptorStatus = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let pollStatus = Darwin.poll(&descriptorStatus, 1, deadline.milliseconds)
        guard pollStatus > 0 else {
            throw AgentClientError.agentUnavailable
        }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(
            descriptor,
            SOL_SOCKET,
            SO_ERROR,
            &socketError,
            &length
        ) == 0, socketError == 0 else {
            throw AgentClientError.agentUnavailable
        }
    }

    private func configureIOTimeouts(_ descriptor: Int32) throws {
        var timeout = timeval(
            tv_sec: Int(deadline.milliseconds / 1_000),
            tv_usec: (deadline.milliseconds % 1_000) * 1_000
        )
        let length = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, length) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, length) == 0 else {
            throw AgentClientError.agentUnavailable
        }
    }
}
