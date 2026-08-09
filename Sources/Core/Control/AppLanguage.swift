import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

public final class AppLanguageStore {
    private static let key = "veloop.language"
    private let defaults: UserDefaults

    public convenience init() {
        self.init(defaults: UserDefaults(suiteName: "com.veloop.shared") ?? .standard)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var language: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: Self.key),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
