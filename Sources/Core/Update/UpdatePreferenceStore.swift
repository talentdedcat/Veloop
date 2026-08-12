import Foundation

public enum UpdatePreferenceAction: Sendable {
    case skip
    case remindLater
    case download
}

public final class UpdatePreferenceStore: @unchecked Sendable {
    private enum Key {
        static let lastAutomaticAttempt = "veloop.update.lastAutomaticAttempt"
        static let skippedVersion = "veloop.update.skippedVersion"
        static let deferredVersion = "veloop.update.deferredVersion"
        static let deferredUntil = "veloop.update.deferredUntil"
    }

    public static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let lock = NSLock()

    public convenience init() {
        self.init(defaults: UserDefaults(suiteName: "com.veloop.shared") ?? .standard)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func isAutomaticCheckDue(at date: Date) -> Bool {
        lock.withLock {
            guard let last = defaults.object(forKey: Key.lastAutomaticAttempt) as? Date else {
                return true
            }
            return date.timeIntervalSince(last) >= Self.automaticCheckInterval
        }
    }

    public func recordAutomaticAttempt(at date: Date) {
        lock.withLock { defaults.set(date, forKey: Key.lastAutomaticAttempt) }
    }

    public func skip(_ version: NumericVersion) {
        record(.skip, for: version, at: Date())
    }

    public func isSkipped(_ version: NumericVersion) -> Bool {
        lock.withLock { defaults.string(forKey: Key.skippedVersion) == version.description }
    }

    public func remindLater(about version: NumericVersion, at date: Date) {
        record(.remindLater, for: version, at: date)
    }

    public func isDeferred(_ version: NumericVersion, at date: Date) -> Bool {
        lock.withLock {
            defaults.string(forKey: Key.deferredVersion) == version.description
                && (defaults.object(forKey: Key.deferredUntil) as? Date).map { date < $0 } == true
        }
    }

    public func record(_ action: UpdatePreferenceAction, for version: NumericVersion, at date: Date) {
        lock.withLock {
            switch action {
            case .skip:
                defaults.set(version.description, forKey: Key.skippedVersion)
                clearDeferral()
            case .remindLater:
                defaults.removeObject(forKey: Key.skippedVersion)
                defaults.set(version.description, forKey: Key.deferredVersion)
                defaults.set(
                    date.addingTimeInterval(Self.automaticCheckInterval),
                    forKey: Key.deferredUntil
                )
            case .download:
                break
            }
        }
    }

    private func clearDeferral() {
        defaults.removeObject(forKey: Key.deferredVersion)
        defaults.removeObject(forKey: Key.deferredUntil)
    }
}
