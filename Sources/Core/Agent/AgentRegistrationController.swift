import Foundation
import ServiceManagement

public final class AgentRegistrationController: AgentLifecycleControlling, @unchecked Sendable {
    typealias Launchctl = @Sendable ([String]) throws -> Int32
    typealias UnregisterLegacyService = @Sendable () throws -> Void
    typealias ResponsivenessProbe = @Sendable () -> Bool
    typealias ReadinessWait = @Sendable () -> Bool

    private static let desiredRegistrationKey = "veloop.startAtLogin"
    private static let legacyMigrationKey = "veloop.didMigrateLegacyLoginItem"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let launchAgentURL: URL
    private let applicationBundleURL: URL
    private let agentExecutableURL: URL
    private let currentBuild: String
    private let unregisterLegacyService: UnregisterLegacyService
    private let launchctl: Launchctl
    private let isAgentResponsive: ResponsivenessProbe
    private let waitForReadiness: ReadinessWait
    private let lock = NSLock()
    private let preferenceQueue = DispatchQueue(
        label: "com.veloop.agent-registration-preference",
        qos: .utility
    )

    public convenience init() {
        let storagePaths = try? StoragePaths.userDefault()
        let probe: ResponsivenessProbe = {
            guard let socketURL = storagePaths?.socket,
                  let response = try? AgentClient(socketURL: socketURL).send(
                    AgentRequest(command: "control-state", arguments: [])
                  ) else {
                return false
            }
            return response.succeeded
        }
        self.init(
            defaults: .standard,
            fileManager: .default,
            launchAgentURL: nil,
            applicationBundleURL: nil,
            currentBuild: nil,
            unregisterLegacyService: {
                try AgentRegistrationController.unregisterLegacyLoginItem()
            },
            launchctl: { arguments in
                try AgentRegistrationController.runLaunchctl(arguments)
            },
            isAgentResponsive: probe,
            waitForReadiness: {
                guard let storagePaths else { return false }
                try? FileManager.default.createDirectory(
                    at: storagePaths.root,
                    withIntermediateDirectories: true
                )
                return AgentReadinessWaiter(
                    socketDirectoryURL: storagePaths.root,
                    probe: probe
                ).wait()
            }
        )
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        launchAgentURL: URL? = nil,
        applicationBundleURL: URL? = nil,
        currentBuild: String? = nil,
        unregisterLegacyService: @escaping UnregisterLegacyService,
        launchctl: @escaping Launchctl,
        isAgentResponsive: @escaping ResponsivenessProbe = { false },
        waitForReadiness: @escaping ReadinessWait = { true }
    ) {
        let appBundle = applicationBundleURL
            ?? URL(fileURLWithPath: "/Applications/Veloop.app", isDirectory: true)
        self.defaults = defaults
        self.fileManager = fileManager
        self.launchAgentURL = launchAgentURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.veloop.service.plist")
        self.applicationBundleURL = appBundle
        agentExecutableURL = appBundle.appendingPathComponent("Contents/MacOS/Veloop")
        self.currentBuild = currentBuild
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "unknown"
        self.unregisterLegacyService = unregisterLegacyService
        self.launchctl = launchctl
        self.isAgentResponsive = isAgentResponsive
        self.waitForReadiness = waitForReadiness
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

    public func restartForPermissionRefresh() throws {
        try lock.withLock {
            try validateApplicationIdentity()
            let shouldRemoveLaunchAgent = !startAtLoginPreference
            do {
                _ = try installLaunchAgent()
                try requireSuccess(["kickstart", "-k", serviceTarget])
                guard waitForReadiness() else {
                    throw AgentRegistrationError.readinessTimedOut
                }
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
    }

    private func ensureRegisteredAndRunningLocked() throws {
        try validateApplicationIdentity()
        if isAgentResponsive() { return }
        try migrateLegacyLoginItemIfNeeded()
        let shouldRemoveLaunchAgent = !startAtLoginPreference
        do {
            let requiresForcedKickstart = try installLaunchAgent()
            try requireSuccess(
                requiresForcedKickstart
                    ? ["kickstart", "-k", serviceTarget]
                    : ["kickstart", serviceTarget]
            )
            guard waitForReadiness() else {
                throw AgentRegistrationError.readinessTimedOut
            }
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

    func setStartAtLoginEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            try validateApplicationIdentity()
            try migrateLegacyLoginItemIfNeeded()
            if enabled {
                _ = try installLaunchAgent()
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

    private func validateApplicationIdentity() throws {
        guard fileManager.fileExists(atPath: agentExecutableURL.path) else {
            throw AgentRegistrationError.invalidApplication
        }
        let infoURL = applicationBundleURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = info as? [String: Any],
              dictionary["CFBundleIdentifier"] as? String == AppConstants.bundleIdentifier,
              dictionary["CFBundleExecutable"] as? String == "Veloop" else {
            throw AgentRegistrationError.invalidApplication
        }
    }

    private func installLaunchAgent() throws -> Bool {
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
        return loaded
    }

    private var domainTarget: String { "gui/\(getuid())" }

    private var serviceTarget: String {
        "\(domainTarget)/\(AppConstants.agentLaunchAgentLabel)"
    }

    private var isLoaded: Bool {
        (try? launchctl(["print", serviceTarget])) == 0
    }

    private func launchAgentData() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": AppConstants.agentLaunchAgentLabel,
                "AssociatedBundleIdentifiers": [AppConstants.bundleIdentifier],
                "EnvironmentVariables": ["VELOOP_BUILD_VERSION": currentBuild],
                "KeepAlive": ["SuccessfulExit": false],
                "ProgramArguments": [agentExecutableURL.path, "--agent"],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ],
            format: .xml,
            options: 0
        )
    }

    private func removeLaunchAgentFile() throws {
        do {
            try fileManager.removeItem(at: launchAgentURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
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
        let service = SMAppService.loginItem(identifier: AppConstants.agentLaunchAgentLabel)
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
    case invalidApplication
    case launchctlFailed(Int32)
    case readinessTimedOut
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
