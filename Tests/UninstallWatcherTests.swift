import Foundation
import XCTest
@testable import VeloopCore

final class UninstallWatcherTests: XCTestCase {
    func testInstallerCopiesPlainExecutableAtomicallyAndBootstrapsJob() throws {
        let harness = try WatcherHarness()
        try harness.createInstalledApplication()
        try Data("watcher-binary".utf8).write(to: harness.bundledExecutable)
        let launchctl = LaunchctlSequence(statuses: [1, 0, 0])
        let installer = UninstallWatcherInstaller(
            bundledExecutableURL: harness.bundledExecutable,
            paths: harness.paths,
            fileManager: .default,
            launchctl: launchctl.call
        )

        try installer.install()

        XCTAssertEqual(try Data(contentsOf: harness.paths.watcherExecutable), Data("watcher-binary".utf8))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: harness.paths.watcherExecutable.path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        let receipt = try JSONDecoder().decode(
            UninstallWatcherReceipt.self,
            from: Data(contentsOf: harness.paths.watcherReceipt)
        )
        XCTAssertEqual(receipt.installedApplicationPath, harness.installedApplication.path)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: harness.paths.watcherLaunchAgent),
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, "com.veloop.uninstall-watcher")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [harness.paths.watcherExecutable.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertFalse(harness.paths.watcherExecutable.path.contains(".app/"))
        XCTAssertEqual(launchctl.calls, [
            ["print", harness.watcherTarget],
            ["bootstrap", harness.domainTarget, harness.paths.watcherLaunchAgent.path],
            ["print", harness.watcherTarget],
        ])
    }

    func testWatcherDoesNothingUntilInstalledReceiptExists() throws {
        let harness = try WatcherHarness()
        let cleanup = CleanupRecorder()
        let watcher = harness.makeWatcher(cleanup: cleanup.call)
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(cleanup.scopes, [])
    }

    func testWatcherChecksCanonicalPathAtStartup() throws {
        let harness = try WatcherHarness()
        try harness.writeReceipt()
        let cleanup = CleanupRecorder()
        let watcher = harness.makeWatcher(cleanup: cleanup.call)
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(cleanup.scopes, [.preserveUserData])
    }

    func testDirectoryEventTriggersCleanupWhenCanonicalAppDisappears() throws {
        let harness = try WatcherHarness()
        try harness.createInstalledApplication()
        try harness.writeReceipt()
        let cleaned = expectation(description: "cleanup after directory event")
        let cleanup = CleanupRecorder(onCall: { cleaned.fulfill() })
        let watcher = harness.makeWatcher(cleanup: cleanup.call)
        addTeardownBlock { watcher.stop() }
        try watcher.start()

        try FileManager.default.removeItem(at: harness.installedApplication)

        wait(for: [cleaned], timeout: 1)
        XCTAssertEqual(cleanup.scopes, [.preserveUserData])
    }

    func testPreservePreferenceSelectsPreserveScope() throws {
        let harness = try WatcherHarness(policy: .preserveUserData)
        try harness.writeReceipt()
        let cleanup = CleanupRecorder()
        let watcher = harness.makeWatcher(cleanup: cleanup.call)
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(cleanup.scopes, [.preserveUserData])
    }

    func testPurgePreferenceSelectsPurgeScope() throws {
        let harness = try WatcherHarness(policy: .purgeUserData)
        try harness.writeReceipt()
        let cleanup = CleanupRecorder()
        let watcher = harness.makeWatcher(cleanup: cleanup.call)
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(cleanup.scopes, [.purgeUserData])
    }

    func testFailedCriticalCleanupKeepsWatcherForRetry() throws {
        let harness = try WatcherHarness()
        try harness.writeReceipt()
        let retried = expectation(description: "cleanup retried and watcher unloaded")
        let cleanup = FailOnceCleanup()
        let unload = Counter()
        let watcher = harness.makeWatcher(
            cleanup: cleanup.call,
            unloadSelf: {
                unload.increment()
                retried.fulfill()
            }
        )
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(cleanup.callCount, 1)
        XCTAssertEqual(unload.value, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.paths.watcherReceipt.path))
        let trigger = harness.applicationsDirectory.appendingPathComponent("retry-trigger")
        XCTAssertTrue(FileManager.default.createFile(atPath: trigger.path, contents: Data()))
        wait(for: [retried], timeout: 1)
        XCTAssertEqual(cleanup.callCount, 2)
        XCTAssertEqual(unload.value, 1)
    }

    func testSuccessfulCleanupRemovesWatcherThenBootsOutItself() throws {
        let harness = try WatcherHarness()
        try harness.writeReceipt()
        let watcherMarker = harness.paths.watcherExecutable
        try Data("watcher".utf8).write(to: watcherMarker)
        let unload = Counter()
        let cleanup: @Sendable (VeloopCleanupScope) throws -> Void = { _ in
            try FileManager.default.removeItem(at: watcherMarker)
        }
        let watcher = harness.makeWatcher(
            cleanup: cleanup,
            unloadSelf: {
                XCTAssertFalse(FileManager.default.fileExists(atPath: watcherMarker.path))
                unload.increment()
            }
        )
        addTeardownBlock { watcher.stop() }

        try watcher.start()

        XCTAssertEqual(unload.value, 1)
    }
}

private enum TestWatcherError: Error {
    case cleanupFailed
}

private final class FailOnceCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    lazy var call: @Sendable (VeloopCleanupScope) throws -> Void = { [self] _ in
        lock.lock()
        calls += 1
        let shouldFail = calls == 1
        lock.unlock()
        if shouldFail { throw TestWatcherError.cleanupFailed }
    }
}

private final class WatcherHarness {
    let root: URL
    let applicationsDirectory: URL
    let installedApplication: URL
    let bundledExecutable: URL
    let paths: VeloopCleanupPaths
    let policyStore: TrashCleanupPreferenceStore
    let domainTarget = "gui/\(getuid())"
    var watcherTarget: String { "\(domainTarget)/com.veloop.uninstall-watcher" }

    init(policy: TrashCleanupPolicy = .preserveUserData) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UninstallWatcherTests-\(UUID().uuidString)")
        applicationsDirectory = root.appendingPathComponent("Applications", isDirectory: true)
        installedApplication = applicationsDirectory.appendingPathComponent("Veloop.app", isDirectory: true)
        bundledExecutable = root.appendingPathComponent("BundledWatcher")
        let home = root.appendingPathComponent("home", isDirectory: true)
        paths = VeloopCleanupPaths(homeDirectory: home, applicationsDirectory: applicationsDirectory)
        try FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: paths.watcherDirectory,
            withIntermediateDirectories: true
        )
        let suiteName = "UninstallWatcherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        policyStore = TrashCleanupPreferenceStore(defaults: defaults)
        policyStore.policy = policy
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func createInstalledApplication() throws {
        try FileManager.default.createDirectory(
            at: installedApplication,
            withIntermediateDirectories: true
        )
    }

    func writeReceipt() throws {
        let data = try JSONEncoder().encode(
            UninstallWatcherReceipt(installedApplicationPath: installedApplication.path)
        )
        try data.write(to: paths.watcherReceipt, options: .atomic)
    }

    func makeWatcher(
        cleanup: @escaping @Sendable (VeloopCleanupScope) throws -> Void,
        unloadSelf: @escaping @Sendable () -> Void = {}
    ) -> InstalledAppWatcher {
        InstalledAppWatcher(
            applicationsDirectory: applicationsDirectory,
            installedApplicationURL: installedApplication,
            receiptURL: paths.watcherReceipt,
            policyStore: policyStore,
            cleanup: cleanup,
            unloadSelf: unloadSelf
        )
    }
}

private final class CleanupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VeloopCleanupScope] = []
    private let error: Error?
    private let onCall: (() -> Void)?

    init(error: Error? = nil, onCall: (() -> Void)? = nil) {
        self.error = error
        self.onCall = onCall
    }

    var scopes: [VeloopCleanupScope] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    lazy var call: @Sendable (VeloopCleanupScope) throws -> Void = { [self] scope in
        lock.lock()
        storage.append(scope)
        lock.unlock()
        onCall?()
        if let error { throw error }
    }
}

private final class LaunchctlSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [Int32]
    private var storage: [[String]] = []

    init(statuses: [Int32]) {
        self.statuses = statuses
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    lazy var call: @Sendable ([String]) throws -> Int32 = { [self] arguments in
        lock.lock()
        defer { lock.unlock() }
        storage.append(arguments)
        return statuses.isEmpty ? 0 : statuses.removeFirst()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
