import Foundation
import ServiceManagement

// The lock serializes every lifecycle and preference operation that touches the
// shared defaults, filesystem, or launchctl collaborators.
public final class AgentRegistrationController: AgentLifecycleControlling, @unchecked Sendable {
    typealias Launchctl = @Sendable ([String]) throws -> Int32
    typealias UnregisterLegacyService = @Sendable () throws -> Void

    private static let label = "com.veloop.service"
    private static let desiredRegistrationKey = "veloop.startAtLogin"
    private static let legacyMigrationKey = "veloop.didMigrateLegacyLoginItem"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let launchAgentURL: URL
    private let agentExecutableURL: URL
    private let currentBuild: String
    private let unregisterLegacyService: UnregisterLegacyService
    private let launchctl: Launchctl
    private let lock = NSLock()
    private let preferenceQueue = DispatchQueue(
        label: "com.veloop.agent-registration-preference",
        qos: .utility
    )

    public convenience init() {
        self.init(
            defaults: .standard,
            fileManager: .default,
            launchAgentURL: nil,
            agentExecutableURL: nil,
            currentBuild: nil,
            unregisterLegacyService: {
                try AgentRegistrationController.unregisterLegacyLoginItem()
            },
            launchctl: { arguments in
                try AgentRegistrationController.runLaunchctl(arguments)
            }
        )
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        launchAgentURL: URL? = nil,
        agentExecutableURL: URL? = nil,
        currentBuild: String? = nil,
        unregisterLegacyService: @escaping UnregisterLegacyService,
        launchctl: @escaping Launchctl
    ) {
        let bundleURL = Self.embeddedAgentBundleURL()
        self.defaults = defaults
        self.fileManager = fileManager
        self.launchAgentURL = launchAgentURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.veloop.service.plist")
        self.agentExecutableURL = agentExecutableURL ?? bundleURL
            .appendingPathComponent("Contents/MacOS/Veloop")
        self.currentBuild = currentBuild
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "unknown"
        self.unregisterLegacyService = unregisterLegacyService
        self.launchctl = launchctl
    }

    public var isStartAtLoginEnabled: Bool {
        startAtLoginPreference
    }

    private var startAtLoginPreference: Bool {
        guard defaults.object(forKey: Self.desiredRegistrationKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.desiredRegistrationKey)
    }

    public func ensureRegisteredAndRunning() throws {
        try lock.withLock {
            try ensureRegisteredAndRunningLocked()
        }
    }

    private func ensureRegisteredAndRunningLocked() throws {
        try migrateLegacyLoginItemIfNeeded()
        let shouldRemoveLaunchAgent = !startAtLoginPreference
        do {
            try installLaunchAgent()
            try requireSuccess(["kickstart", serviceTarget])
            try requireSuccess(["print", serviceTarget])
        } catch {
            if shouldRemoveLaunchAgent {
                try? removeLaunchAgentFile()
            }
            throw error
        }
        if shouldRemoveLaunchAgent {
            try removeLaunchAgentFile()
        }
    }

    private func installLaunchAgent() throws {
        let data = try launchAgentData()
        var loaded = isLoaded
        if (try? Data(contentsOf: launchAgentURL)) != data {
            if loaded {
                try requireSuccess(["bootout", serviceTarget])
                loaded = false
            }
            try fileManager.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchAgentURL, options: .atomic)
        }
        if !loaded {
            try requireSuccess(["bootstrap", domainTarget, launchAgentURL.path])
        }
    }

    func setStartAtLoginEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            try migrateLegacyLoginItemIfNeeded()
            if enabled {
                try installLaunchAgent()
                try requireSuccess(["kickstart", serviceTarget])
                try requireSuccess(["print", serviceTarget])
            } else {
                try removeLaunchAgentFile()
            }
            defaults.set(enabled, forKey: Self.desiredRegistrationKey)
        }
    }

    public func setStartAtLoginEnabled(
        _ enabled: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        preferenceQueue.async { [self] in
            do {
                try setStartAtLoginEnabled(enabled)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    public func restartRegisteredAgent() throws {
        try lock.withLock {
            try ensureRegisteredAndRunningLocked()
            try requireSuccess(["kickstart", "-k", serviceTarget])
        }
    }

    private var domainTarget: String {
        "gui/\(getuid())"
    }

    private var serviceTarget: String {
        "\(domainTarget)/\(Self.label)"
    }

    private var isLoaded: Bool {
        (try? launchctl(["print", serviceTarget])) == 0
    }

    private func launchAgentData() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": Self.label,
                "AssociatedBundleIdentifiers": ["com.veloop.app"],
                "EnvironmentVariables": ["VELOOP_BUILD_VERSION": currentBuild],
                "KeepAlive": ["SuccessfulExit": false],
                "ProgramArguments": [agentExecutableURL.path],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ],
            format: .xml,
            options: 0
        )
    }

    private func removeLaunchAgentFile() throws {
        guard fileManager.fileExists(atPath: launchAgentURL.path) else { return }
        try fileManager.removeItem(at: launchAgentURL)
    }

    private func migrateLegacyLoginItemIfNeeded() throws {
        guard !defaults.bool(forKey: Self.legacyMigrationKey) else { return }
        try unregisterLegacyService()
        defaults.set(true, forKey: Self.legacyMigrationKey)
    }

    private func requireSuccess(_ arguments: [String]) throws {
        let status = try launchctl(arguments)
        guard status == 0 else {
            throw AgentRegistrationError.launchctlFailed(status)
        }
    }

    private static func embeddedAgentBundleURL() -> URL {
        let loginItems = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems")
        return loginItems.appendingPathComponent("Veloop.app")
    }

    private static func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func unregisterLegacyLoginItem() throws {
        let service = SMAppService.loginItem(identifier: label)
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
    }
}

private enum AgentRegistrationError: Error {
    case launchctlFailed(Int32)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
