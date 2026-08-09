import Foundation

final class ManifestStore<Value: Codable> {
    private let url: URL
    private let corruptedDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    init(url: URL, corruptedDirectory: URL) {
        self.url = url
        self.corruptedDirectory = corruptedDirectory
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else {
            let value = defaultValue()
            try saveUnlocked(value)
            return value
        }

        do {
            return try decoder.decode(Value.self, from: Data(contentsOf: url))
        } catch {
            try quarantineUnlocked()
            let value = defaultValue()
            try saveUnlocked(value)
            return value
        }
    }

    func save(_ value: Value) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(value)
    }

    private func saveUnlocked(_ value: Value) throws {
        try AtomicFileWriter.replace(try encoder.encode(value), at: url)
    }

    private func quarantineUnlocked() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: corruptedDirectory, withIntermediateDirectories: true)
        let name = "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
        let destination = corruptedDirectory.appendingPathComponent(name)
        try fileManager.moveItem(at: url, to: destination)
    }
}
