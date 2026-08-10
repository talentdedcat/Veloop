import Foundation

struct StoragePaths {
    let root: URL

    var configuration: URL { root.appendingPathComponent("config.json") }
    var history: URL { root.appendingPathComponent("history.json") }
    var blobs: URL { root.appendingPathComponent("blobs", isDirectory: true) }
    var files: URL { root.appendingPathComponent("files", isDirectory: true) }
    var corrupted: URL { root.appendingPathComponent("corrupted", isDirectory: true) }
    var socket: URL { root.appendingPathComponent("agent.sock") }
    var processLock: URL { root.appendingPathComponent("agent.lock") }
    var permissionIdentityReceipt: URL { root.appendingPathComponent("permission-identity.json") }
    var uninstallWatcherDirectory: URL {
        root.appendingPathComponent("UninstallWatcher", isDirectory: true)
    }

    static func userDefault(fileManager: FileManager = .default) throws -> StoragePaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return StoragePaths(root: applicationSupport.appendingPathComponent("Veloop", isDirectory: true))
    }

    func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, blobs, files, corrupted] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
