import AppKit
import VeloopCore

enum SoftwareUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(String)
    case failed
}

@MainActor
final class UpdateCoordinator {
    var onChange: (() -> Void)?
    private(set) var status: SoftwareUpdateStatus = .idle {
        didSet { onChange?() }
    }

    private let checker: UpdateChecker
    private let preferences: UpdatePreferenceStore
    private let localization: LocalizationController
    private var updateWindowController: UpdateWindowController?
    private var automaticallyPresentedVersions: Set<NumericVersion> = []
    private var checkRevision: UInt64 = 0

    init(
        checker: UpdateChecker,
        preferences: UpdatePreferenceStore,
        localization: LocalizationController
    ) {
        self.checker = checker
        self.preferences = preferences
        self.localization = localization
    }

    func checkAutomatically() {
        runCheck(.automatic, manual: false)
    }

    func checkManually() {
        guard status != .checking else { return }
        status = .checking
        runCheck(.manual, manual: true)
    }

    private func runCheck(_ mode: UpdateCheckMode, manual: Bool) {
        checkRevision &+= 1
        let revision = checkRevision
        Task { [weak self] in
            guard let self else { return }
            let result = await checker.check(mode)
            guard revision == checkRevision else { return }
            handle(result, manual: manual)
        }
    }

    private func handle(_ result: UpdateCheckResult, manual: Bool) {
        switch result {
        case .suppressed:
            if manual { status = .idle }
        case .upToDate:
            if manual { status = .upToDate }
        case let .available(manifest):
            status = .available(manifest.version.description)
            if manual || automaticallyPresentedVersions.insert(manifest.version).inserted {
                present(manifest)
            }
        case .failed:
            if manual { status = .failed }
        }
    }

    private func present(_ manifest: UpdateManifest) {
        updateWindowController?.close()
        let controller = UpdateWindowController(
            manifest: manifest,
            localization: localization,
            actionHandler: { [weak self] action in
                self?.perform(action, for: manifest)
            }
        )
        updateWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func perform(_ action: UpdateWindowAction, for manifest: UpdateManifest) {
        switch action {
        case .skip:
            preferences.record(.skip, for: manifest.version, at: Date())
            updateWindowController?.close()
        case .remindLater:
            preferences.record(.remindLater, for: manifest.version, at: Date())
            updateWindowController?.close()
        case .download:
            guard NSWorkspace.shared.open(manifest.releaseURL) else {
                updateWindowController?.showDownloadError()
                return
            }
            updateWindowController?.close()
        }
    }
}
