import Foundation

public struct UpdateManifest: Equatable, Sendable {
    public let version: NumericVersion
    public let releaseURL: URL
    private let englishNotes: [String]
    private let simplifiedChineseNotes: [String]

    init(
        version: NumericVersion,
        releaseURL: URL,
        englishNotes: [String],
        simplifiedChineseNotes: [String]
    ) {
        self.version = version
        self.releaseURL = releaseURL
        self.englishNotes = englishNotes
        self.simplifiedChineseNotes = simplifiedChineseNotes
    }

    public func notes(
        for language: AppLanguage,
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations
    ) -> [String] {
        switch language {
        case .english:
            return englishNotes
        case .simplifiedChinese:
            return simplifiedChineseNotes
        case .system:
            let usesChinese = preferredLocalizations.first?.lowercased().hasPrefix("zh-hans") == true
            return usesChinese ? simplifiedChineseNotes : englishNotes
        }
    }
}

public struct UpdateManifestDecoder: Sendable {
    public static let maximumBodyBytes = 65_536
    public static let maximumNotesPerLanguage = 32
    public static let maximumNoteScalars = 500

    public init() {}

    public func decode(_ data: Data) throws -> UpdateManifest {
        guard data.count <= Self.maximumBodyBytes else { throw UpdateManifestError.invalid }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1,
              let version = try? NumericVersion(document.version),
              let releaseURL = URL(string: document.releaseURL),
              Self.isTrusted(releaseURL, version: version),
              Self.valid(document.notes.en),
              Self.valid(document.notes.simplifiedChinese) else {
            throw UpdateManifestError.invalid
        }
        return UpdateManifest(
            version: version,
            releaseURL: releaseURL,
            englishNotes: document.notes.en,
            simplifiedChineseNotes: document.notes.simplifiedChinese
        )
    }

    private static func valid(_ notes: [String]) -> Bool {
        !notes.isEmpty
            && notes.count <= maximumNotesPerLanguage
            && notes.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.unicodeScalars.count <= maximumNoteScalars
            }
    }

    private static func isTrusted(_ url: URL, version: NumericVersion) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.user == nil
            && components.password == nil
            && components.fragment == nil
            && components.query == nil
            && components.percentEncodedPath
                == "/talentdedcat/Veloop/releases/tag/v\(version.description)"
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let version: String
        let releaseURL: String
        let notes: Notes
    }

    private struct Notes: Decodable {
        let en: [String]
        let simplifiedChinese: [String]

        private enum CodingKeys: String, CodingKey {
            case en
            case simplifiedChinese = "zh-Hans"
        }
    }
}

private enum UpdateManifestError: Error {
    case invalid
}
