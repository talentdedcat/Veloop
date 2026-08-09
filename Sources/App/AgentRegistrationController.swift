import Foundation
import ServiceManagement

final class AgentRegistrationController {
    typealias Launchctl = ([String]) throws -> Int32
    typealias UnregisterLegacyService = () throws -> Void

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

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        launchAgentURL: URL? = nil,
        agentExecutableURL: URL? = nil,
        currentBuild: String? = nil,
        unregisterLegacyService: @escaping UnregisterLegacyService = AgentRegistrationController.unregisterLegacyLoginItem,
        launchctl: @escaping Launchctl = AgentRegistrationController.runLaunchctl
    ) {
        let bundleURL = Self.embeddedAgentBundleURL(fileManager: fileManager)
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

    var isStartAtLoginEnabled: Bool {
        guard defaults.object(forKey: Self.desiredRegistrationKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.desiredRegistrationKey)
    }

    func ensureRegistered() throws {
        try migrateLegacyLoginItemIfNeeded()
        guard isStartAtLoginEnabled else {
            try removeLaunchAgentFile()
            return
        }

        try installLaunchAgent()
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
        try migrateLegacyLoginItemIfNeeded()
        if enabled {
            try installLaunchAgent()
        } else {
            try removeLaunchAgentFile()
        }
        defaults.set(enabled, forKey: Self.desiredRegistrationKey)
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

    private static func embeddedAgentBundleURL(fileManager: FileManager) -> URL {
        let loginItems = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems")
        let packaged = loginItems.appendingPathComponent("Veloop.app")
        if fileManager.fileExists(atPath: packaged.path) {
            return packaged
        }
        return loginItems.appendingPathComponent("VeloopService.app")
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
