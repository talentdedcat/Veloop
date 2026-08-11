import Foundation

public struct VeloopCleanupPaths: Sendable {
    public let applicationSupportRoot: URL
    public let configuration: URL
    public let history: URL
    public let blobs: URL
    public let files: URL
    public let corrupted: URL
    public let socket: URL
    public let processLock: URL
    public let permissionIdentityReceipt: URL
    public let paletteHostMarker: URL
    public let agentRuntimeDirectory: URL
    public let agentRuntimeBundle: URL
    public let legacyAgentRuntimeBundle: URL
    public let agentRuntimeExecutable: URL
    public let watcherDirectory: URL
    public let watcherExecutable: URL
    public let watcherReceipt: URL
    public let agentLaunchAgent: URL
    public let watcherLaunchAgent: URL
    public let installedApplicationBundle: URL
    public let paletteBundle: URL
    public let sharedAgentBundle: URL
    public let userAgentBundle: URL
    public let cachePaths: [URL]
    public let preferencePaths: [URL]
    public let savedStatePaths: [URL]
    public let webKitPaths: [URL]

    public init(homeDirectory: URL, applicationsDirectory: URL) {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let applicationSupport = library.appendingPathComponent(
            "Application Support/Veloop",
            isDirectory: true
        )
        applicationSupportRoot = applicationSupport
        configuration = applicationSupport.appendingPathComponent("config.json")
        history = applicationSupport.appendingPathComponent("history.json")
        blobs = applicationSupport.appendingPathComponent("blobs", isDirectory: true)
        files = applicationSupport.appendingPathComponent("files", isDirectory: true)
        corrupted = applicationSupport.appendingPathComponent("corrupted", isDirectory: true)
        socket = applicationSupport.appendingPathComponent("agent.sock")
        processLock = applicationSupport.appendingPathComponent("agent.lock")
        permissionIdentityReceipt = applicationSupport.appendingPathComponent(
            "permission-identity.json"
        )
        paletteHostMarker = applicationSupport.appendingPathComponent("palette-host-path")
        agentRuntimeDirectory = applicationSupport.appendingPathComponent(
            "AgentRuntime",
            isDirectory: true
        )
        agentRuntimeBundle = agentRuntimeDirectory.appendingPathComponent(
            "Veloop.app",
            isDirectory: true
        )
        legacyAgentRuntimeBundle = agentRuntimeDirectory.appendingPathComponent(
            "Veloop",
            isDirectory: true
        )
        agentRuntimeExecutable = agentRuntimeBundle.appendingPathComponent(
            "Contents/MacOS/Veloop"
        )
        watcherDirectory = applicationSupport.appendingPathComponent(
            "UninstallWatcher",
            isDirectory: true
        )
        watcherExecutable = watcherDirectory.appendingPathComponent("VeloopUninstallWatcher")
        watcherReceipt = watcherDirectory.appendingPathComponent("receipt.json")
        agentLaunchAgent = library.appendingPathComponent(
            "LaunchAgents/com.veloop.service.plist"
        )
        watcherLaunchAgent = library.appendingPathComponent(
            "LaunchAgents/com.veloop.uninstall-watcher.plist"
        )
        installedApplicationBundle = applicationsDirectory.appendingPathComponent(
            "Veloop.app",
            isDirectory: true
        )
        paletteBundle = library.appendingPathComponent(
            "Input Methods/VeloopPalette.app",
            isDirectory: true
        )
        sharedAgentBundle = applicationsDirectory.appendingPathComponent(
            "Veloop Agent.app",
            isDirectory: true
        )
        userAgentBundle = homeDirectory.appendingPathComponent(
            "Applications/Veloop Agent.app",
            isDirectory: true
        )
        cachePaths = [
            library.appendingPathComponent("Caches/com.veloop.app", isDirectory: true),
            library.appendingPathComponent(
                "Caches/com.veloop.diagnostics.carethost",
                isDirectory: true
            ),
            library.appendingPathComponent("Caches/com.veloop.service", isDirectory: true),
        ]
        preferencePaths = [
            library.appendingPathComponent("Preferences/com.veloop.app.plist"),
            library.appendingPathComponent("Preferences/com.veloop.service.plist"),
            library.appendingPathComponent("Preferences/com.veloop.shared.plist"),
        ]
        savedStatePaths = [
            library.appendingPathComponent(
                "Saved Application State/com.veloop.app.savedState",
                isDirectory: true
            ),
        ]
        webKitPaths = [
            library.appendingPathComponent(
                "WebKit/com.veloop.diagnostics.carethost",
                isDirectory: true
            ),
        ]
    }

    public static func userDefault(fileManager: FileManager = .default) -> Self {
        Self(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            applicationsDirectory: URL(fileURLWithPath: "/Applications", isDirectory: true)
        )
    }

    public var functionalRuntimePaths: [URL] {
        [
            socket,
            processLock,
            permissionIdentityReceipt,
            paletteHostMarker,
            legacyAgentRuntimeBundle,
            agentRuntimeBundle,
            agentRuntimeDirectory,
            agentLaunchAgent,
            paletteBundle,
            sharedAgentBundle,
            userAgentBundle,
        ]
    }

    public var watcherPaths: [URL] {
        [watcherExecutable, watcherReceipt, watcherDirectory, watcherLaunchAgent]
    }

    public var userDataPaths: [URL] {
        [configuration, history, blobs, files, corrupted]
            + cachePaths
            + preferencePaths
            + savedStatePaths
            + webKitPaths
    }

    public var allKnownPaths: [URL] {
        functionalRuntimePaths + watcherPaths + userDataPaths + [applicationSupportRoot]
    }
}
