import Darwin
import Foundation

public struct UninstallWatcherReceipt: Codable, Equatable, Sendable {
    public let installedApplicationPath: String

    public init(installedApplicationPath: String) {
        self.installedApplicationPath = installedApplicationPath
    }
}

public struct UninstallWatcherInstaller: @unchecked Sendable {
    public typealias Launchctl = @Sendable ([String]) throws -> Int32

    private let bundledExecutableURL: URL
    private let paths: VeloopCleanupPaths
    private let fileManager: FileManager
    private let launchctl: Launchctl

    public init(
        bundledExecutableURL: URL,
        paths: VeloopCleanupPaths = .userDefault(),
        fileManager: FileManager = .default,
        launchctl: @escaping Launchctl
    ) {
        self.bundledExecutableURL = bundledExecutableURL
        self.paths = paths
        self.fileManager = fileManager
        self.launchctl = launchctl
    }

    public func install() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: paths.installedApplicationBundle.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw UninstallWatcherInstallerError.missingInstalledApplication
        }
        let bundledData = try Data(contentsOf: bundledExecutableURL, options: .mappedIfSafe)
        let executableChanged = (try? Data(
            contentsOf: paths.watcherExecutable,
            options: .mappedIfSafe
        )) != bundledData

        try fileManager.createDirectory(
            at: paths.watcherDirectory,
            withIntermediateDirectories: true
        )
        if executableChanged {
            try replaceExecutable(with: bundledData)
        }

        let receiptData = try encodedReceipt()
        try AtomicFileWriter.replace(receiptData, at: paths.watcherReceipt)

        let launchAgentData = try makeLaunchAgentData()
        let launchAgentChanged = (try? Data(contentsOf: paths.watcherLaunchAgent)) != launchAgentData
        if launchAgentChanged {
            try AtomicFileWriter.replace(launchAgentData, at: paths.watcherLaunchAgent)
        }

        let loaded = try launchctl(["print", watcherTarget]) == 0
        if loaded, executableChanged || launchAgentChanged {
            try requireSuccess(["bootout", watcherTarget])
        }
        if !loaded || executableChanged || launchAgentChanged {
            try requireSuccess([
                "bootstrap",
                domainTarget,
                paths.watcherLaunchAgent.path,
            ])
        }
        try requireSuccess(["print", watcherTarget])
    }

    private var domainTarget: String { "gui/\(getuid())" }
    private var watcherTarget: String {
        "\(domainTarget)/\(AppConstants.uninstallWatcherLabel)"
    }

    private func replaceExecutable(with data: Data) throws {
        let temporary = paths.watcherDirectory.appendingPathComponent(
            ".install-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            guard chmod(temporary.path, 0o755) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard rename(temporary.path, paths.watcherExecutable.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func encodedReceipt() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            UninstallWatcherReceipt(
                installedApplicationPath: paths.installedApplicationBundle.standardizedFileURL.path
            )
        )
    }

    private func makeLaunchAgentData() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": AppConstants.uninstallWatcherLabel,
                "KeepAlive": true,
                "ProcessType": "Background",
                "ProgramArguments": [paths.watcherExecutable.path],
                "RunAtLoad": true,
            ],
            format: .xml,
            options: 0
        )
    }

    private func requireSuccess(_ arguments: [String]) throws {
        let status = try launchctl(arguments)
        guard status == 0 else {
            throw UninstallWatcherInstallerError.launchctlFailed(status)
        }
    }
}

private enum UninstallWatcherInstallerError: Error {
    case missingInstalledApplication
    case launchctlFailed(Int32)
}
