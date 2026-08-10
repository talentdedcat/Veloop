import Darwin
import Foundation

public final class InstalledAppWatcher: @unchecked Sendable {
    public typealias Cleanup = @Sendable (VeloopCleanupScope) throws -> Void
    public typealias UnloadSelf = @Sendable () -> Void

    private let applicationsDirectory: URL
    private let installedApplicationURL: URL
    private let receiptURL: URL
    private let policyStore: TrashCleanupPreferenceStore
    private let cleanup: Cleanup
    private let unloadSelf: UnloadSelf
    private let queue = DispatchQueue(label: "com.veloop.uninstall-watcher")
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var cleanupInProgress = false
    private var cleanupCompleted = false

    public init(
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications"),
        installedApplicationURL: URL = URL(fileURLWithPath: "/Applications/Veloop.app"),
        receiptURL: URL,
        policyStore: TrashCleanupPreferenceStore,
        cleanup: @escaping Cleanup,
        unloadSelf: @escaping UnloadSelf
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.installedApplicationURL = installedApplicationURL
        self.receiptURL = receiptURL
        self.policyStore = policyStore
        self.cleanup = cleanup
        self.unloadSelf = unloadSelf
    }

    public static func live() throws -> InstalledAppWatcher {
        let paths = VeloopCleanupPaths.userDefault()
        let cleanupController = VeloopCleanupController.live(paths: paths)
        return InstalledAppWatcher(
            receiptURL: paths.watcherReceipt,
            policyStore: TrashCleanupPreferenceStore(),
            cleanup: { scope in
                try cleanupController.cleanup(scope: scope, includeWatcher: true)
            },
            unloadSelf: {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = [
                    "bootout",
                    "gui/\(getuid())/\(AppConstants.uninstallWatcherLabel)",
                ]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
                Darwin.exit(0)
            }
        )
    }

    public func start() throws {
        let descriptor = Darwin.open(applicationsDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            self?.evaluateInstalledPath()
        }
        newSource.setCancelHandler {
            Darwin.close(descriptor)
        }

        lock.lock()
        guard source == nil else {
            lock.unlock()
            newSource.cancel()
            throw InstalledAppWatcherError.alreadyStarted
        }
        source = newSource
        lock.unlock()

        newSource.resume()
        evaluateInstalledPath()
    }

    public func stop() {
        lock.lock()
        let current = source
        source = nil
        lock.unlock()
        current?.cancel()
    }

    private func evaluateInstalledPath() {
        guard let receipt = try? JSONDecoder().decode(
            UninstallWatcherReceipt.self,
            from: Data(contentsOf: receiptURL)
        ) else {
            return
        }
        guard URL(fileURLWithPath: receipt.installedApplicationPath)
            .standardizedFileURL.path == installedApplicationURL.standardizedFileURL.path else {
            return
        }
        guard !FileManager.default.fileExists(atPath: installedApplicationURL.path) else {
            return
        }

        lock.lock()
        guard !cleanupInProgress, !cleanupCompleted else {
            lock.unlock()
            return
        }
        cleanupInProgress = true
        lock.unlock()

        do {
            let scope: VeloopCleanupScope = policyStore.policy == .purgeUserData
                ? .purgeUserData
                : .preserveUserData
            try cleanup(scope)
            lock.lock()
            cleanupInProgress = false
            cleanupCompleted = true
            lock.unlock()
            stop()
            unloadSelf()
        } catch {
            lock.lock()
            cleanupInProgress = false
            lock.unlock()
            AppLogger.failure(category: "uninstall-watcher", error: error)
        }
    }
}

private enum InstalledAppWatcherError: Error {
    case alreadyStarted
}
