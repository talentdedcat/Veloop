import AppKit
import VeloopCore

enum UpdateWindowAction {
    case skip
    case remindLater
    case download
}

@MainActor
final class UpdateWindowController: NSWindowController {
    private let actionHandler: (UpdateWindowAction) -> Void
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    init(
        manifest: UpdateManifest,
        localization: LocalizationController,
        actionHandler: @escaping (UpdateWindowAction) -> Void
    ) {
        self.actionHandler = actionHandler
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string("update.window.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let heading = NSTextField(labelWithString: localization.string(
            "update.window.heading",
            manifest.version.description
        ))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)

        let notesLabel = NSTextField(wrappingLabelWithString: manifest.notes(
            for: localization.language
        ).map { "• \($0)" }.joined(separator: "\n\n"))
        notesLabel.font = .systemFont(ofSize: 14)
        notesLabel.maximumNumberOfLines = 0
        notesLabel.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(notesLabel)
        NSLayoutConstraint.activate([
            notesLabel.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 4),
            notesLabel.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -4),
            notesLabel.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            notesLabel.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -4),
            documentView.widthAnchor.constraint(equalToConstant: 496),
        ])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.stringValue = localization.string("update.error.openDownload")
        errorLabel.isHidden = true

        let skipButton = NSButton(
            title: localization.string("update.action.skip"),
            target: self,
            action: #selector(skip)
        )
        let remindButton = NSButton(
            title: localization.string("update.action.remindLater"),
            target: self,
            action: #selector(remindLater)
        )
        let downloadButton = NSButton(
            title: localization.string("update.action.download"),
            target: self,
            action: #selector(download)
        )
        downloadButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [skipButton, NSView(), remindButton, downloadButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.views[1].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = NSStackView(views: [heading, scrollView, errorLabel, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56),
            scrollView.heightAnchor.constraint(equalToConstant: 190),
            errorLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDownloadError() {
        errorLabel.isHidden = false
    }

    @objc private func skip() { actionHandler(.skip) }
    @objc private func remindLater() { actionHandler(.remindLater) }
    @objc private func download() { actionHandler(.download) }
}
