import Foundation

public enum TrashCleanupPolicy: String, Codable, CaseIterable, Sendable {
    case preserveUserData
    case purgeUserData
}

public final class TrashCleanupPreferenceStore: @unchecked Sendable {
    public static let suiteName = "com.veloop.shared"
    public static let key = "veloop.trashCleanupPolicy"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = UserDefaults(
            suiteName: TrashCleanupPreferenceStore.suiteName
        )!
    ) {
        self.defaults = defaults
    }

    public var policy: TrashCleanupPolicy {
        get {
            withLock {
                guard let rawValue = defaults.string(forKey: Self.key),
                      let policy = TrashCleanupPolicy(rawValue: rawValue) else {
                    return .preserveUserData
                }
                return policy
            }
        }
        set {
            withLock {
                defaults.set(newValue.rawValue, forKey: Self.key)
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
