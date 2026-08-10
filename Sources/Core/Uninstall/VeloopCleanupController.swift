import AppKit
import Darwin
import Foundation

public enum VeloopCleanupScope: Equatable, Sendable {
    case preserveUserData
    case purgeUserData
}

public final class VeloopCleanupController: @unchecked Sendable {
    public typealias Launchctl = @Sendable ([String]) throws -> Int32
    public typealias TerminatePalette = @Sendable () throws -> Void

    private let paths: VeloopCleanupPaths
    private let fileManager: FileManager
    private let permissionResetter: any TCCPermissionResetting
    private let launchctl: Launchctl
    private let terminatePalette: TerminatePalette

    public init(
        paths: VeloopCleanupPaths = .userDefault(),
        fileManager: FileManager = .default,
        permissionResetter: any TCCPermissionResetting,
        launchctl: @escaping Launchctl,
        terminatePalette: @escaping TerminatePalette
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.permissionResetter = permissionResetter
        self.launchctl = launchctl
        self.terminatePalette = terminatePalette
    }

    public static func live(paths: VeloopCleanupPaths = .userDefault()) -> Self {
        Self(
            paths: paths,
            permissionResetter: TCCPermissionResetter(),
            launchctl: { arguments in try Self.runLaunchctl(arguments) },
            terminatePalette: { try Self.terminatePaletteApplications() }
        )
    }

    public func cleanup(scope: VeloopCleanupScope, includeWatcher: Bool) throws {
        try stopAgentIfLoaded()
        try terminatePalette()
        try permissionResetter.resetVeloopPermissions()
        try remove(paths.functionalRuntimePaths)

        if scope == .purgeUserData {
            try remove(paths.userDataPaths)
        }
        if includeWatcher {
            try remove(paths.watcherPaths)
        }
        if scope == .purgeUserData, includeWatcher {
            try remove([paths.applicationSupportRoot])
        }
    }

    private func stopAgentIfLoaded() throws {
        let target = "gui/\(getuid())/\(AppConstants.agentLaunchAgentLabel)"
        guard try launchctl(["print", target]) == 0 else { return }
        let status = try launchctl(["bootout", target])
        guard status == 0 else {
            throw VeloopCleanupError.launchctlFailed(status)
        }
    }

    private func remove(_ urls: [URL]) throws {
        let ordered = Set(urls).sorted {
            $0.pathComponents.count > $1.pathComponents.count
        }
        for url in ordered {
            do {
                try fileManager.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                continue
            }
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

    private static func terminatePaletteApplications() throws {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.talentdedcat.veloop.palette"
        ) {
            application.terminate()
            let deadline = Date().addingTimeInterval(0.5)
            while !application.isTerminated, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            if !application.isTerminated,
               Darwin.kill(application.processIdentifier, SIGTERM) != 0,
               errno != ESRCH {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}

private enum VeloopCleanupError: Error {
    case launchctlFailed(Int32)
}
