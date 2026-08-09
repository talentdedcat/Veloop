import AppKit
import VeloopCore

final class ControlWindowController: NSWindowController {
    private let localization: LocalizationController

    init(
        localization: LocalizationController,
        model: ControlViewModel,
        registrationController: AgentRegistrationController
    ) {
        self.localization = localization
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string("app.title")
        window.isReleasedWhenClosed = false
        window.contentViewController = ControlViewController(
            localization: localization,
            model: model,
            registrationController: registrationController
        )

        super.init(window: window)
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.contentMaxSize = NSSize(width: 680, height: 460)
        window.setContentSize(NSSize(width: 680, height: 460))
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
        window?.setContentSize(NSSize(width: 680, height: 460))
        window?.center()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func languageDidChange() {
        window?.title = localization.string("app.title")
    }
}
