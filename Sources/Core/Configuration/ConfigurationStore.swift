import Foundation

final class ConfigurationStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try save(.default)
            return .default
        }

        let configuration = try decoder.decode(Configuration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    func save(_ configuration: Configuration) throws {
        try configuration.validate()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(configuration).write(to: url, options: [.atomic])
    }
}
