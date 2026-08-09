import AppKit
import VeloopCore

@MainActor
final class ControlViewController: NSViewController {
    private let localization: LocalizationController
    private let model: ControlViewModel
    private let registrationController: AgentRegistrationController

    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDetailLabel = NSTextField(labelWithString: "")
    private let masterSwitch = NSSwitch()
    private let startAtLoginSwitch = NSSwitch()
    private let previewsSwitch = NSSwitch()
    private let historyField = NSTextField()
    private let historyStepper = NSStepper()
    private let historyUnitLabel = NSTextField(labelWithString: "")
    private let storageField = NSTextField()
    private let storageStepper = NSStepper()
    private let storageUnitLabel = NSTextField(labelWithString: "MB")
    private let inputStatusImage = NSImageView()
    private let inputStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusImage = NSImageView()
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let inputSettingsButton = NSButton()
    private let accessibilitySettingsButton = NSButton()
    private let languagePopup = NSPopUpButton()
    private let openDataButton = NSButton()
    private let clearButton = NSButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let behaviorTitle = NSTextField(labelWithString: "")
    private let startAtLoginLabel = NSTextField(labelWithString: "")
    private let previewsLabel = NSTextField(labelWithString: "")
    private let storageTitle = NSTextField(labelWithString: "")
    private let historyLimitLabel = NSTextField(labelWithString: "")
    private let storageLimitLabel = NSTextField(labelWithString: "")
    private let permissionsTitle = NSTextField(labelWithString: "")
    private let inputPermissionLabel = NSTextField(labelWithString: "")
    private let accessibilityPermissionLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private var localErrorKey: String?
    private var startAtLoginRevision: UInt64 = 0

    init(
        localization: LocalizationController,
        model: ControlViewModel,
        registrationController: AgentRegistrationController
    ) {
        self.localization = localization
        self.model = model
        self.registrationController = registrationController
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 680, height: 460)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 460))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildInterface()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onChange = { [weak self] in self?.render() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .veloopLanguageDidChange,
            object: localization
        )
        applyLocalization()
        render()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildInterface() {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(outer)
        let append: (NSView) -> Void = { child in
            outer.addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        }

        let icon = NSImageView()
        icon.image = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setFrameSize(NSSize(width: 44, height: 44))
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusDetailLabel.font = .systemFont(ofSize: 12)
        statusDetailLabel.textColor = .secondaryLabelColor
        let statusStack = NSStackView(views: [statusLabel, statusDetailLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 3
        let header = row([icon, statusStack, flexibleSpace(), masterSwitch], spacing: 14)
        constrainHeight(header, 68)
        append(header)
        append(separator())

        configureSectionTitle(behaviorTitle)
        constrainHeight(behaviorTitle, 20)
        append(behaviorTitle)
        let loginRow = labeledRow(startAtLoginLabel, control: startAtLoginSwitch)
        let previewRow = labeledRow(previewsLabel, control: previewsSwitch)
        constrainHeight(loginRow, 42)
        constrainHeight(previewRow, 42)
        append(loginRow)
        append(previewRow)
        append(separator())

        configureSectionTitle(storageTitle)
        constrainHeight(storageTitle, 20)
        append(storageTitle)
        let historyInput = configureLimitInput(
            field: historyField,
            unitLabel: historyUnitLabel,
            stepper: historyStepper,
            increment: 1
        )
        let storageInput = configureLimitInput(
            field: storageField,
            unitLabel: storageUnitLabel,
            stepper: storageStepper,
            increment: Double(ControlLimitInput.storageStepMegabytes)
        )
        let storageRow = row([
            historyLimitLabel, historyInput, flexibleSpace(), storageLimitLabel, storageInput,
        ], spacing: 10)
        constrainHeight(storageRow, 44)
        append(storageRow)
        append(separator())

        configureSectionTitle(permissionsTitle)
        constrainHeight(permissionsTitle, 20)
        append(permissionsTitle)
        let inputRow = permissionRow(
            title: inputPermissionLabel,
            image: inputStatusImage,
            status: inputStatusLabel,
            button: inputSettingsButton
        )
        let accessibilityRow = permissionRow(
            title: accessibilityPermissionLabel,
            image: accessibilityStatusImage,
            status: accessibilityStatusLabel,
            button: accessibilitySettingsButton
        )
        constrainHeight(inputRow, 42)
        constrainHeight(accessibilityRow, 42)
        append(inputRow)
        append(accessibilityRow)
        append(separator())

        languagePopup.widthAnchor.constraint(equalToConstant: 142).isActive = true
        let footer = row([
            languageLabel, languagePopup, flexibleSpace(), openDataButton, clearButton,
        ], spacing: 10)
        constrainHeight(footer, 44)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        constrainHeight(errorLabel, 20)
        append(footer)
        append(errorLabel)

        masterSwitch.target = self
        masterSwitch.action = #selector(masterChanged)
        startAtLoginSwitch.target = self
        startAtLoginSwitch.action = #selector(startAtLoginChanged)
        previewsSwitch.target = self
        previewsSwitch.action = #selector(previewsChanged)
        historyField.target = self
        historyField.action = #selector(historyLimitSubmitted)
        historyField.cell?.sendsActionOnEndEditing = true
        historyStepper.target = self
        historyStepper.action = #selector(historyStepperChanged)
        storageField.target = self
        storageField.action = #selector(storageLimitSubmitted)
        storageField.cell?.sendsActionOnEndEditing = true
        storageStepper.target = self
        storageStepper.action = #selector(storageStepperChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        inputSettingsButton.target = self
        inputSettingsButton.action = #selector(openInputSettings)
        accessibilitySettingsButton.target = self
        accessibilitySettingsButton.action = #selector(openAccessibilitySettings)
        openDataButton.target = self
        openDataButton.action = #selector(openDataFolder)
        clearButton.target = self
        clearButton.action = #selector(confirmClearHistory)

        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            outer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            outer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            outer.heightAnchor.constraint(equalToConstant: 408),
        ])
    }

    private func applyLocalization() {
        behaviorTitle.stringValue = localization.string("behavior.title")
        startAtLoginLabel.stringValue = localization.string("behavior.startAtLogin")
        previewsLabel.stringValue = localization.string("behavior.previews")
        storageTitle.stringValue = localization.string("storage.title")
        historyLimitLabel.stringValue = localization.string("storage.historyLimit")
        storageLimitLabel.stringValue = localization.string("storage.diskLimit")
        historyUnitLabel.stringValue = localization.string("unit.items")
        historyField.setAccessibilityLabel(historyLimitLabel.stringValue)
        historyStepper.setAccessibilityLabel(historyLimitLabel.stringValue)
        storageField.setAccessibilityLabel(storageLimitLabel.stringValue)
        storageStepper.setAccessibilityLabel(storageLimitLabel.stringValue)
        permissionsTitle.stringValue = localization.string("permissions.title")
        inputPermissionLabel.stringValue = localization.string("permissions.inputMonitoring")
        accessibilityPermissionLabel.stringValue = localization.string("permissions.accessibility")
        languageLabel.stringValue = localization.string("language.label")
        configureButton(inputSettingsButton, titleKey: "action.openSettings", symbol: "gearshape")
        configureButton(accessibilitySettingsButton, titleKey: "action.openSettings", symbol: "gearshape")
        configureButton(openDataButton, titleKey: "action.openData", symbol: "folder")
        configureButton(clearButton, titleKey: "action.clearHistory", symbol: "trash")
        rebuildLanguageMenu()
        render()
    }

    private func render() {
        let state = model.state
        if state == nil {
            statusLabel.stringValue = localization.string(model.isLoading ? "status.loading" : "status.unavailable")
            statusDetailLabel.stringValue = ""
        } else if state?.enabled == true {
            statusLabel.stringValue = localization.string("status.enabled")
            statusDetailLabel.stringValue = localization.string(
                "status.detail",
                state?.historyCount ?? 0,
                formattedBytes(state?.storageBytes ?? 0)
            )
        } else {
            statusLabel.stringValue = localization.string("status.paused")
            statusDetailLabel.stringValue = localization.string(
                "status.detail",
                state?.historyCount ?? 0,
                formattedBytes(state?.storageBytes ?? 0)
            )
        }

        masterSwitch.state = state?.enabled == true ? .on : .off
        startAtLoginSwitch.state = registrationController.isStartAtLoginEnabled ? .on : .off
        previewsSwitch.state = state?.configuration.showContentPreviews == true ? .on : .off
        if historyField.currentEditor() == nil, let historyCount = state?.configuration.maximumHistoryCount {
            historyField.integerValue = historyCount
            historyStepper.maxValue = max(historyStepper.maxValue, Double(historyCount))
            historyStepper.integerValue = historyCount
        }
        if storageField.currentEditor() == nil, let bytes = state?.configuration.maximumDiskBytes {
            let text = ControlLimitInput.megabyteText(for: bytes)
            storageField.stringValue = text
            if let megabytes = Double(text) {
                storageStepper.maxValue = max(storageStepper.maxValue, megabytes)
                storageStepper.doubleValue = megabytes
            }
        }
        let inputAllowed = state?.permissions.listenEvents ?? false
        let accessibilityAllowed = state?.permissions.accessibility ?? false
        renderPermission(inputAllowed, image: inputStatusImage, label: inputStatusLabel)
        renderPermission(accessibilityAllowed, image: accessibilityStatusImage, label: accessibilityStatusLabel)

        let controlsEnabled = state != nil && !model.isLoading
        masterSwitch.isEnabled = controlsEnabled
        previewsSwitch.isEnabled = controlsEnabled
        historyField.isEnabled = controlsEnabled
        historyStepper.isEnabled = controlsEnabled
        storageField.isEnabled = controlsEnabled
        storageStepper.isEnabled = controlsEnabled
        clearButton.isEnabled = controlsEnabled && (state?.historyCount ?? 0) > 0
        inputSettingsButton.isEnabled = !inputAllowed
        accessibilitySettingsButton.isEnabled = !accessibilityAllowed

        let errorKey = localErrorKey ?? model.inlineError.map(errorKey(for:))
        errorLabel.stringValue = errorKey.map(localization.string) ?? ""
    }

    private func rebuildLanguageMenu() {
        languagePopup.removeAllItems()
        let entries: [(AppLanguage, String)] = [
            (.system, "language.system"),
            (.english, "language.english"),
            (.simplifiedChinese, "language.simplifiedChinese"),
        ]
        for (index, entry) in entries.enumerated() {
            languagePopup.addItem(withTitle: localization.string(entry.1))
            languagePopup.item(at: index)?.representedObject = entry.0.rawValue
        }
        if let index = entries.firstIndex(where: { $0.0 == localization.language }) {
            languagePopup.selectItem(at: index)
        }
    }

    private func renderPermission(_ allowed: Bool, image: NSImageView, label: NSTextField) {
        let symbol = allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.contentTintColor = allowed ? .systemGreen : .systemOrange
        label.stringValue = localization.string(allowed ? "permissions.allowed" : "permissions.missing")
        label.textColor = allowed ? .secondaryLabelColor : .labelColor
    }

    @objc private func languageDidChange() {
        applyLocalization()
    }

    @objc private func masterChanged() {
        localErrorKey = nil
        Task { await model.update(ControlUpdate(enabled: masterSwitch.state == .on)) }
    }

    @objc private func startAtLoginChanged() {
        let enabled = startAtLoginSwitch.state == .on
        startAtLoginRevision &+= 1
        let revision = startAtLoginRevision
        let registrationController = registrationController
        registrationController.setStartAtLoginEnabled(enabled) { [weak self] succeeded in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard revision == self.startAtLoginRevision else { return }
                localErrorKey = succeeded ? nil : "error.registrationFailed"
                render()
            }
        }
    }

    @objc private func previewsChanged() {
        localErrorKey = nil
        Task { await model.update(ControlUpdate(showContentPreviews: previewsSwitch.state == .on)) }
    }

    @objc private func historyLimitSubmitted() {
        guard let count = ControlLimitInput.historyCount(from: historyField.stringValue) else {
            rejectLimitInput()
            return
        }
        localErrorKey = nil
        Task { await model.update(ControlUpdate(maximumHistoryCount: count)) }
    }

    @objc private func historyStepperChanged() {
        historyField.integerValue = historyStepper.integerValue
        historyLimitSubmitted()
    }

    @objc private func storageLimitSubmitted() {
        guard let bytes = ControlLimitInput.storageBytes(fromMegabytes: storageField.stringValue) else {
            rejectLimitInput()
            return
        }
        localErrorKey = nil
        Task { await model.update(ControlUpdate(maximumDiskBytes: bytes)) }
    }

    @objc private func storageStepperChanged() {
        storageField.integerValue = storageStepper.integerValue
        storageLimitSubmitted()
    }

    private func rejectLimitInput() {
        localErrorKey = "error.invalidLimit"
        view.window?.makeFirstResponder(nil)
        render()
    }

    @objc private func languageChanged() {
        guard let rawValue = languagePopup.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else { return }
        localization.language = language
    }

    @objc private func openInputSettings() {
        openSystemSettings("Privacy_ListenEvent", permissionGroup: .inputMonitoring)
    }

    @objc private func openAccessibilitySettings() {
        openSystemSettings("Privacy_Accessibility", permissionGroup: .accessibility)
    }

    private func openSystemSettings(_ pane: String, permissionGroup: EventPermissionGroup) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            model.markPermissionRefreshPending()
            NSWorkspace.shared.open(url)
        }
        Task { await model.requestPermissions(permissionGroup) }
    }

    @objc private func openDataFolder() {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        NSWorkspace.shared.open(applicationSupport.appendingPathComponent("Veloop", isDirectory: true))
    }

    @objc private func confirmClearHistory() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = localization.string("clear.title")
        alert.informativeText = localization.string("clear.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localization.string("clear.confirm"))
        alert.addButton(withTitle: localization.string("clear.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { await self.model.clearHistory() }
        }
    }

    private func errorKey(for error: ControlViewModelError) -> String {
        switch error {
        case .agentUnavailable: return "error.agentUnavailable"
        case .updateFailed: return "error.updateFailed"
        case .clearFailed: return "error.clearFailed"
        case .permissionRequestFailed: return "error.permissionRequestFailed"
        case .restartFailed: return "error.restartFailed"
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func configureSectionTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
    }

    private func configureButton(_ button: NSButton, titleKey: String, symbol: String) {
        button.title = localization.string(titleKey)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)
        button.imagePosition = .imageLeading
    }

    private func configureLimitInput(
        field: NSTextField,
        unitLabel: NSTextField,
        stepper: NSStepper,
        increment: Double
    ) -> NSStackView {
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.placeholderString = "1"
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        unitLabel.alignment = .left
        unitLabel.textColor = .secondaryLabelColor
        unitLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        stepper.minValue = 1
        stepper.maxValue = 1_000_000
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.autorepeat = true
        let editor = row([field, unitLabel, stepper], spacing: 4)
        editor.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return editor
    }

    private func labeledRow(_ label: NSTextField, control: NSView) -> NSStackView {
        row([label, flexibleSpace(), control], spacing: 10)
    }

    private func permissionRow(
        title: NSTextField,
        image: NSImageView,
        status: NSTextField,
        button: NSButton
    ) -> NSStackView {
        title.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        image.widthAnchor.constraint(equalToConstant: 16).isActive = true
        image.heightAnchor.constraint(equalToConstant: 16).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        return row([title, flexibleSpace(), image, status, button], spacing: 8)
    }

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func flexibleSpace() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        constrainHeight(separator, 1)
        return separator
    }

    private func constrainHeight(_ view: NSView, _ height: CGFloat) {
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

}
