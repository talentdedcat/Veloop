import AppKit
import VeloopCore

final class ControlWindowController: NSWindowController {
    static let contentSize = NSSize(width: 680, height: 460)

    private let localization: LocalizationController

    init(
        localization: LocalizationController,
        model: ControlViewModel,
        registrationController: AgentRegistrationController,
        trashCleanupStore: TrashCleanupPreferenceStore = TrashCleanupPreferenceStore()
    ) {
        self.localization = localization
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string("app.title")
        window.isReleasedWhenClosed = false
        window.contentViewController = ControlViewController(
            localization: localization,
            model: model,
            registrationController: registrationController,
            trashCleanupStore: trashCleanupStore
        )

        super.init(window: window)
        window.contentMinSize = Self.contentSize
        window.contentMaxSize = Self.contentSize
        window.setContentSize(Self.contentSize)
        window.center()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .veloopLanguageDidChange,
            object: localization
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.setContentSize(Self.contentSize)
        window?.center()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func languageDidChange() {
        window?.title = localization.string("app.title")
    }
}
