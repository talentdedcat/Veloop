import Foundation
import VeloopCore

extension Notification.Name {
    static let veloopLanguageDidChange = Notification.Name("com.veloop.languageDidChange")
}

final class LocalizationController {
    private let store: AppLanguageStore

    init(store: AppLanguageStore = AppLanguageStore()) {
        self.store = store
    }

    var language: AppLanguage {
        get { store.language }
        set {
            guard store.language != newValue else { return }
            store.language = newValue
            NotificationCenter.default.post(name: .veloopLanguageDidChange, object: self)
        }
    }

    func string(_ key: String) -> String {
        resolvedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    private var resolvedBundle: Bundle {
        guard let identifier = language.localizationIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
