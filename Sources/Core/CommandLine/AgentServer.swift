import Darwin
import Foundation

enum AgentServerError: Error, Equatable {
    case socketPathTooLong
    case socketCreationFailed
    case bindFailed
    case listenFailed
}

final class AgentServer {
    private let socketURL: URL
    private let clientTimeoutMilliseconds: Int
    private let handler: (AgentRequest) -> AgentResponse
    private let queue = DispatchQueue(label: "com.veloop.service-ipc")
    private let lock = NSLock()
    private var listeningDescriptor: Int32 = -1

    init(
        socketURL: URL,
        clientTimeoutMilliseconds: Int = 1_000,
        handler: @escaping (AgentRequest) -> AgentResponse
    ) {
        self.socketURL = socketURL
        self.clientTimeoutMilliseconds = max(1, clientTimeoutMilliseconds)
        self.handler = handler
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listeningDescriptor < 0 else {
            return
        }
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: socketURL)

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentServerError.socketCreationFailed
        }
        var noPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))

        do {
            let result = try withUnixAddress(path: socketURL.path) { address, length in
                Darwin.bind(descriptor, address, length)
            }
            guard result == 0 else {
                throw AgentServerError.bindFailed
            }
            guard chmod(socketURL.path, 0o600) == 0 else {
                throw AgentServerError.bindFailed
            }
            guard Darwin.listen(descriptor, 4) == 0 else {
                throw AgentServerError.listenFailed
            }
        } catch {
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: socketURL)
            throw error
        }

        listeningDescriptor = descriptor
        queue.async { [weak self] in
            self?.acceptLoop(descriptor: descriptor)
        }
    }

    func stop() {
        lock.lock()
        let descriptor = listeningDescriptor
        listeningDescriptor = -1
        lock.unlock()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptLoop(descriptor: Int32) {
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                return
            }
            guard configureTimeouts(for: client) else {
                Darwin.close(client)
                continue
            }
            handleClient(client)
            Darwin.close(client)
        }
    }

    private func configureTimeouts(for descriptor: Int32) -> Bool {
        var timeout = timeval(
            tv_sec: clientTimeoutMilliseconds / 1_000,
            tv_usec: Int32(clientTimeoutMilliseconds % 1_000) * 1_000
        )
        let size = socklen_t(MemoryLayout<timeval>.size)
        return setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size) == 0
            && setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size) == 0
    }

    private func handleClient(_ descriptor: Int32) {
        var peerUserID: uid_t = 0
        var peerGroupID: gid_t = 0
        guard getpeereid(descriptor, &peerUserID, &peerGroupID) == 0, peerUserID == geteuid() else {
            return
        }
        do {
            let request = try AgentProtocolCodec.decodeRequest(readMessage(from: descriptor))
            try writeMessage(AgentProtocolCodec.encode(handler(request)), to: descriptor)
        } catch let error as AgentProtocolError {
            let response: AgentResponse = error == .messageTooLarge
                ? .failure("request too large")
                : .failure("malformed request")
            try? writeMessage(AgentProtocolCodec.encode(response), to: descriptor)
        } catch {
            try? writeMessage(AgentProtocolCodec.encode(AgentResponse.failure("request failed")), to: descriptor)
        }
    }

    deinit {
        stop()
    }
}

func withUnixAddress<T>(
    path: String,
    body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) throws -> T {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else {
        throw AgentServerError.socketPathTooLong
    }
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: bytes)
    }
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

func readMessage(from descriptor: Int32) throws -> Data {
    var message = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while message.count <= AgentProtocolCodec.maximumMessageBytes {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count > 0 else {
            throw AgentProtocolError.malformedMessage
        }
        message.append(buffer, count: count)
        if let newline = message.firstIndex(of: 0x0a) {
            return Data(message[..<newline])
        }
    }
    throw AgentProtocolError.messageTooLarge
}

func writeMessage(_ data: Data, to descriptor: Int32) throws {
    var offset = 0
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }
        while offset < data.count {
            let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
            guard count > 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            offset += count
        }
    }
}
