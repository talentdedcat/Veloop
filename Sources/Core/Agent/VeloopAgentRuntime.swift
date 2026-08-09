import AppKit
import Foundation

public final class VeloopAgentRuntime {
    private let paths: StoragePaths
    private let configurationStore: ConfigurationStore
    private let historyStore: HistoryStore
    private let capturer: PasteboardCapturer
    private let permissions: EventPermissionController
    private let monitor: PasteboardMonitor
    private let processLock: ProcessLock
    private let processRestarter: AgentProcessRestarter
    private let previewPreference: PreviewContentPreference
    private let caretLocator: CaretLocator
    private var inputSubsystem: InputSubsystemCoordinator!
    private let stateLock = NSLock()
    private var activeServer: AgentServer?
    private var configuration: Configuration
    private var enabled: Bool
    private var started = false

    public init() throws {
        let paths = try StoragePaths.userDefault()
        try paths.createDirectories()
        let configurationStore = ConfigurationStore(url: paths.configuration)
        let configuration: Configuration
        do {
            configuration = try configurationStore.load()
        } catch {
            AppLogger.failure(category: "configuration-load", error: error)
            try? FileManager.default.moveItem(
                at: paths.configuration,
                to: paths.corrupted.appendingPathComponent("config-\(UUID().uuidString).json")
            )
            try configurationStore.save(.default)
            configuration = .default
        }

        let blobStore = try BlobStore(rootURL: paths.blobs)
        let fileStore = try FileSnapshotStore(rootURL: paths.files)
        let historyStore = try HistoryStore(
            paths: paths,
            configuration: configuration,
            blobStore: blobStore,
            fileStore: fileStore
        )
        // Synthetic events stop key recursion, while this transaction stops pasteboard recapture;
        // neither mechanism alone covers both independent system event streams.
        let transaction = RestorationTransaction()
        let capturer = PasteboardCapturer(
            blobStore: blobStore,
            fileStore: fileStore,
            policy: PasteboardCapturePolicy(configuration: configuration),
            maximumSingleSnapshotBytes: configuration.effectiveMaximumSnapshotBytes
        )
        let restorer = PasteboardRestorer(
            blobStore: blobStore,
            fileStore: fileStore,
            transaction: transaction
        )
        let permissions = EventPermissionController()
        let injector = PasteEventInjector()
        let previewPreference = PreviewContentPreference(value: configuration.showContentPreviews)
        let languageStore = AppLanguageStore()
        let caretLocator = CaretLocator.shared
        let placementResolver = FocusStackPlacementResolver(caretBounds: {
            caretLocator.currentCaretLocation()?.globalRect
        })
        let placementSession = FocusStackPlacementSession {
            placementResolver.frame(panelSize: FocusStackPanelSurface.size)
        }
        let focusStackPresenter = FocusStackPresenter(
            surface: FocusStackPanelSurface(imageLoader: ImagePreviewLoader(blobReader: blobStore)),
            frameBuilder: FocusStackFrameBuilder(
                previewBuilder: PastePreviewBuilder(
                    blobReader: blobStore,
                    language: { languageStore.language }
                ),
                snapshot: { historyStore.snapshot(id: $0) },
                acquireLease: { historyStore.acquireLease(for: $0) }
            ),
            showContent: { previewPreference.value },
            placement: {
                placementSession.frame()
            }
        )
        let presentationRelay = CyclePresentationRelay { event in
            focusStackPresenter.handle(event)
            switch event {
            case .selected:
                break
            case .cancelled, .committing, .interrupted:
                placementSession.reset()
            }
        }

        self.paths = paths
        self.configurationStore = configurationStore
        self.historyStore = historyStore
        self.capturer = capturer
        self.permissions = permissions
        self.previewPreference = previewPreference
        self.caretLocator = caretLocator
        self.configuration = configuration
        self.enabled = configuration.startEnabled
        self.processLock = ProcessLock(url: paths.processLock)
        self.processRestarter = AgentProcessRestarter()
        self.monitor = PasteboardMonitor(
            capturer: capturer,
            historyStore: historyStore,
            transaction: transaction,
            pollIntervalMilliseconds: configuration.pollIntervalMilliseconds
        )
        let postPaste = { injector.postPaste() }

        let cycleController = PasteCycleController(
            historyIDs: { historyStore.snapshotIDs() },
            canCycle: { [weak permissions, weak self] in
                guard let self else {
                    return false
                }
                return self.isEnabled
                    && permissions?.status().canCycle == true
                    && placementSession.prepare()
            },
            canContinueCycle: { [weak permissions, weak self] in
                guard let self else {
                    return false
                }
                return self.isEnabled && permissions?.status().canCycle == true
            },
            present: presentationRelay.publish,
            commit: { snapshotID in
                guard let lease = historyStore.acquireLease(for: snapshotID) else {
                    _ = postPaste()
                    return
                }
                defer { lease.release() }
                guard let snapshot = historyStore.snapshot(id: snapshotID) else {
                    _ = postPaste()
                    return
                }
                do {
                    _ = try restorer.restore(snapshot, to: .general)
                } catch {
                    AppLogger.failure(category: "restore", error: error)
                    _ = postPaste()
                    return
                }
                guard postPaste() else { return }
                do {
                    _ = try historyStore.markRecentlyUsed(snapshotID)
                } catch {
                    AppLogger.failure(category: "history-lru", error: error)
                }
            }
        )
        let eventTap = EventTapManager(controller: cycleController)
        self.inputSubsystem = InputSubsystemCoordinator(
            startListening: { eventTap.start() },
            stopListening: { eventTap.stop() },
            activatePalette: {
                MainActor.assumeIsolated {
                    PaletteInputSourceActivator.activateDuringStartup()
                }
            },
            deactivatePalette: {
                _ = PaletteInputSourceActivator.deactivate()
            }
        )
    }

    public func start() throws {
        precondition(Thread.isMainThread)
        guard !started else {
            return
        }
        try processLock.acquire()

        let runtimeServer = AgentServer(socketURL: paths.socket) { [weak self] request in
            self?.handle(request) ?? .failure("agent is stopping")
        }
        try replaceServerAndStart(runtimeServer)
        monitor.start()
        monitor.setEnabled(isEnabled)
        synchronizeInputSubsystem()
        started = true
        AppLogger.lifecycle("started")
    }

    public func stop() {
        precondition(Thread.isMainThread)
        guard started else {
            return
        }
        inputSubsystem.stop()
        monitor.stop()
        activeServer?.stop()
        processLock.release()
        started = false
        AppLogger.lifecycle("stopped")
    }

    private var isEnabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return enabled
    }

    private func replaceServerAndStart(_ server: AgentServer) throws {
        activeServer = server
        try server.start()
    }

    private func handle(_ request: AgentRequest) -> AgentResponse {
        switch request.command {
        case "status":
            return .success("enabled=\(isEnabled)\nhistoryCount=\(historyStore.count)\nstorageBytes=\(historyStore.storageBytes)")
        case "pause":
            return setEnabled(false)
        case "resume":
            return setEnabled(true)
        case "clear":
            do {
                try historyStore.clear()
                return .success("cleared")
            } catch {
                return .failure("clear failed")
            }
        case "count":
            return .success(String(historyStore.count))
        case "storage":
            return .success(String(historyStore.storageBytes))
        case "doctor":
            let status = permissions.status()
            let paletteStatus = PaletteInputSourceActivator.status()
            return .success(
                "listenEvents=\(status.listenEvents)\n" +
                    "postEvents=\(status.postEvents)\n" +
                    "accessibility=\(status.accessibility)\n" +
                    "paletteInstalled=\(paletteStatus.installed)\n" +
                    "paletteEnabled=\(paletteStatus.enabled)\n" +
                    "paletteSelected=\(paletteStatus.selected)"
            )
        case "caret-diagnostic":
            return encodedResponse(caretLocator.diagnosticReport())
        case "config-get":
            return configurationResponse()
        case "config-set":
            return setConfiguration(arguments: request.arguments)
        case "control-state":
            return encodedResponse(controlState())
        case "control-update":
            return applyControlUpdate(arguments: request.arguments)
        case "request-permissions":
            return encodedResponse(requestPermissionStatus())
        case "restart":
            processRestarter.restart(bundleURL: Bundle.main.bundleURL) { [weak self] in
                self?.stop()
            }
            return .success("restarting")
        default:
            return .failure("unknown command")
        }
    }

    private func setEnabled(_ value: Bool) -> AgentResponse {
        stateLock.lock()
        enabled = value
        configuration.startEnabled = value
        let updated = configuration
        stateLock.unlock()
        do {
            try configurationStore.save(updated)
            DispatchQueue.main.async { [weak self] in
                self?.monitor.setEnabled(value)
                self?.synchronizeInputSubsystem()
            }
            return .success(value ? "resumed" : "paused")
        } catch {
            return .failure("configuration save failed")
        }
    }

    private func configurationResponse() -> AgentResponse {
        stateLock.lock()
        let value = configuration
        stateLock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value), let output = String(data: data, encoding: .utf8) else {
            return .failure("configuration encoding failed")
        }
        return .success(output)
    }

    private func controlState() -> ControlState {
        stateLock.lock()
        let currentConfiguration = configuration
        let currentEnabled = enabled
        stateLock.unlock()
        return ControlState(
            enabled: currentEnabled,
            historyCount: historyStore.count,
            storageBytes: historyStore.storageBytes,
            configuration: currentConfiguration,
            permissions: permissions.status()
        )
    }

    private func applyControlUpdate(arguments: [String]) -> AgentResponse {
        guard arguments.count == 1,
              let data = arguments[0].data(using: .utf8),
              let update = try? JSONDecoder().decode(ControlUpdate.self, from: data) else {
            return .failure("invalid control update")
        }

        stateLock.lock()
        var updatedConfiguration = configuration
        let previousConfiguration = configuration
        var updatedEnabled = enabled
        stateLock.unlock()

        if let value = update.enabled {
            updatedEnabled = value
            updatedConfiguration.startEnabled = value
        }
        if let value = update.showContentPreviews {
            updatedConfiguration.showContentPreviews = value
        }
        if let value = update.maximumHistoryCount {
            updatedConfiguration.maximumHistoryCount = value
        }
        if let value = update.maximumDiskBytes {
            updatedConfiguration.maximumDiskBytes = value
        }

        do {
            try updatedConfiguration.validate()
            try configurationStore.save(updatedConfiguration)
            if previousConfiguration.maximumHistoryCount != updatedConfiguration.maximumHistoryCount
                || previousConfiguration.maximumDiskBytes != updatedConfiguration.maximumDiskBytes {
                try historyStore.updateConfiguration(updatedConfiguration)
            }
            capturer.updateMaximumSingleSnapshotBytes(
                updatedConfiguration.effectiveMaximumSnapshotBytes
            )
            stateLock.lock()
            configuration = updatedConfiguration
            enabled = updatedEnabled
            stateLock.unlock()
            previewPreference.value = updatedConfiguration.showContentPreviews
            DispatchQueue.main.async { [weak self] in
                self?.monitor.setEnabled(updatedEnabled)
                self?.synchronizeInputSubsystem()
            }
            return encodedResponse(controlState())
        } catch {
            return .failure("control update failed")
        }
    }

    private func requestPermissionStatus() -> EventPermissionStatus {
        if Thread.isMainThread {
            let status = permissions.request()
            synchronizeInputSubsystem(listenEvents: status.listenEvents)
            return status
        }
        return DispatchQueue.main.sync { [self] in
            let status = permissions.request()
            synchronizeInputSubsystem(listenEvents: status.listenEvents)
            return status
        }
    }

    private func encodedResponse<T: Encodable>(_ value: T) -> AgentResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let output = String(data: data, encoding: .utf8) else {
            return .failure("response encoding failed")
        }
        return .success(output)
    }

    private func setConfiguration(arguments: [String]) -> AgentResponse {
        guard arguments.count == 2 else {
            return .failure("config set requires key and value")
        }
        stateLock.lock()
        var updated = configuration
        stateLock.unlock()
        guard applyConfigurationValue(key: arguments[0], value: arguments[1], configuration: &updated) else {
            return .failure("invalid configuration key or value")
        }
        do {
            try updated.validate()
            try configurationStore.save(updated)
            try historyStore.updateConfiguration(updated)
            capturer.updateMaximumSingleSnapshotBytes(updated.effectiveMaximumSnapshotBytes)
            stateLock.lock()
            configuration = updated
            enabled = updated.startEnabled
            stateLock.unlock()
            previewPreference.value = updated.showContentPreviews
            DispatchQueue.main.async { [weak self] in
                self?.monitor.setEnabled(updated.startEnabled)
                self?.synchronizeInputSubsystem()
            }
            return .success("saved; restart applies capture-policy and polling changes")
        } catch {
            return .failure("invalid configuration")
        }
    }

    private func applyConfigurationValue(
        key: String,
        value: String,
        configuration: inout Configuration
    ) -> Bool {
        switch key {
        case "maximumHistoryCount":
            guard let parsed = Int(value) else { return false }
            configuration.maximumHistoryCount = parsed
        case "maximumDiskBytes":
            guard let parsed = UInt64(value) else { return false }
            configuration.maximumDiskBytes = parsed
        case "maximumSingleSnapshotBytes":
            guard let parsed = UInt64(value) else { return false }
            configuration.maximumSingleSnapshotBytes = parsed
        case "pollIntervalMilliseconds":
            guard let parsed = Int(value) else { return false }
            configuration.pollIntervalMilliseconds = parsed
        case "captureConcealed":
            guard let parsed = Bool(value) else { return false }
            configuration.captureConcealed = parsed
        case "captureTransient":
            guard let parsed = Bool(value) else { return false }
            configuration.captureTransient = parsed
        case "captureAutoGenerated":
            guard let parsed = Bool(value) else { return false }
            configuration.captureAutoGenerated = parsed
        case "startEnabled":
            guard let parsed = Bool(value) else { return false }
            configuration.startEnabled = parsed
        case "showContentPreviews":
            guard let parsed = Bool(value) else { return false }
            configuration.showContentPreviews = parsed
        default:
            return false
        }
        return true
    }

    private func synchronizeInputSubsystem(listenEvents: Bool? = nil) {
        precondition(Thread.isMainThread)
        inputSubsystem.synchronize(
            enabled: isEnabled,
            listenEvents: listenEvents ?? permissions.status().listenEvents
        )
    }
}

private final class PreviewContentPreference {
    private let lock = NSLock()
    private var storedValue: Bool

    init(value: Bool) {
        storedValue = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
