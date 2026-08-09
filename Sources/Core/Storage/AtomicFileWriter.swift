import Darwin
import Foundation

enum AtomicFileWriter {
    static func replace(_ data: Data, at destination: URL, permissions: Int16? = nil) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")

        do {
            try data.write(to: temporary, options: [.withoutOverwriting])
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            if let permissions {
                guard chmod(temporary.path, mode_t(permissions)) == 0 else {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
            }
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}
