import Darwin
import Foundation

enum ProcessLockError: Error, Equatable {
    case alreadyRunning
    case unavailable
}

final class ProcessLock {
    private let url: URL
    private var descriptor: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    func acquire() throws {
        guard descriptor < 0 else {
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let opened = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard opened >= 0 else {
            throw ProcessLockError.unavailable
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(opened)
            throw ProcessLockError.alreadyRunning
        }
        descriptor = opened
        let processID = Data("\(getpid())\n".utf8)
        _ = ftruncate(opened, 0)
        try? writeMessage(processID, to: opened)
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
