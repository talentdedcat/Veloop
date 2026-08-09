import AppKit
import Foundation
import QuartzCore

final class FocusStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FocusStackPanelSurface: FocusStackSurface {
    static let size = NSSize(width: 348, height: 148)

    private let panel: FocusStackPanel
    private let container: NSView
    private let animator: DepthPushAnimator
    private let imageLoader: ImagePreviewLoader
    private let imageQueue = DispatchQueue(
        label: "com.veloop.preview-image",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    private var imageGeneration: UInt64 = 0

    init(imageLoader: ImagePreviewLoader) {
        self.imageLoader = imageLoader
        panel = Self.makePanel()
        container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        animator = DepthPushAnimator(container: container)

        panel.contentView = container
    }

    static func makePanel() -> FocusStackPanel {
        let panel = FocusStackPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    var isVisible: Bool { panel.isVisible }

    func show(frame: FocusStackFrame, at panelFrame: NSRect, animated: Bool) {
        precondition(Thread.isMainThread)
        imageGeneration &+= 1
        let generation = imageGeneration
        let view = FocusStackFrameView(frame: frame)
        panel.setFrame(panelFrame, display: false)
        if animated {
            animator.transition(
                to: view,
                direction: frame.direction,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        } else {
            animator.install(view)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        loadSelectedImage(in: frame, into: view, generation: generation)
    }

    func hide(animated: Bool) {
        precondition(Thread.isMainThread)
        imageGeneration &+= 1
        panel.orderOut(nil)
        animator.cancel()
    }

    func releaseTransientResources() {
        imageGeneration &+= 1
        imageLoader.clear()
    }

    private func loadSelectedImage(
        in frame: FocusStackFrame,
        into view: FocusStackFrameView,
        generation: UInt64
    ) {
        guard case let .image(blobHash) = frame.selected.content else { return }
        imageQueue.async { [weak self, weak view] in
            guard let self else { return }
            let image = try? self.imageLoader.image(for: blobHash)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.imageGeneration == generation, let image else { return }
                view?.setSelectedImage(NSImage(cgImage: image, size: .zero))
            }
        }
    }
}

final class FocusStackFrameView: NSView {
    private let selectedCard: FocusStackCardView
    private let newerTab: FocusStackTypeTabView
    private let olderTab: FocusStackTypeTabView

    var selectedFrame: NSRect { selectedCard.frame }
    var newerTabFrame: NSRect { newerTab.frame }
    var olderTabFrame: NSRect { olderTab.frame }
    var newerTabIsHidden: Bool { newerTab.isHidden }
    var olderTabIsHidden: Bool { olderTab.isHidden }

    init(frame model: FocusStackFrame) {
        selectedCard = FocusStackCardView(
            preview: model.selected,
            position: "\(model.position) / \(model.count)",
            emphasized: true
        )
        newerTab = FocusStackTypeTabView(preview: model.newer, edge: .lower)
        olderTab = FocusStackTypeTabView(preview: model.older, edge: .upper)
        super.init(frame: NSRect(origin: .zero, size: FocusStackPanelSurface.size))
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        for view in [newerTab, olderTab, selectedCard] {
            addSubview(view)
        }
        newerTab.frame = NSRect(x: 49, y: 0, width: 250, height: 32)
        selectedCard.frame = NSRect(x: 0, y: 22, width: 348, height: 104)
        olderTab.frame = NSRect(x: 49, y: 116, width: 250, height: 32)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedImage(_ image: NSImage) {
        selectedCard.setImage(image)
    }

    func animateTabsIn(after delay: TimeInterval, duration: TimeInterval) {
        guard delay > 0 else { return }
        for tab in [newerTab, olderTab] where !tab.isHidden {
            guard let layer = tab.layer else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.beginTime = CACurrentMediaTime() + delay
            animation.duration = duration
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "veloop.tab-reveal")
        }
    }
}

private final class FocusStackTypeTabView: NSView {
    enum Edge { case upper, lower }

    private let swatch = NSView()
    private let label = NSTextField(labelWithString: "")

    init(preview: PastePreview?, edge: Edge) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.08
        layer?.shadowRadius = 5
        layer?.shadowOffset = NSSize(width: 0, height: edge == .upper ? 2 : -2)
        isHidden = preview == nil

        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 3
        swatch.layer?.backgroundColor = Self.accent(for: preview).cgColor
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Self.accent(for: preview)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = preview?.title ?? ""
        addSubview(swatch)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let labelWidth = min(label.intrinsicContentSize.width + 8, bounds.width - 42)
        let groupWidth = 8 + 6 + labelWidth
        let startX = round((bounds.width - groupWidth) / 2)
        swatch.frame = NSRect(x: startX, y: 12, width: 8, height: 8)
        label.frame = NSRect(x: startX + 14, y: 8, width: labelWidth, height: 16)
    }

    static func accent(for preview: PastePreview?) -> NSColor {
        guard let preview else { return .tertiaryLabelColor }
        switch preview.content {
        case .text: return NSColor(red: 0.35, green: 0.28, blue: 0.79, alpha: 1)
        case .image: return NSColor(red: 0.04, green: 0.50, blue: 0.55, alpha: 1)
        case .files: return NSColor(red: 0.63, green: 0.39, blue: 0.04, alpha: 1)
        case .metadata: return .secondaryLabelColor
        }
    }

}

private final class FocusStackCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(wrappingLabelWithString: "")
    private let imageView = NSImageView()
    private let emphasized: Bool

    init(preview: PastePreview?, position: String = "", emphasized: Bool) {
        self.emphasized = emphasized
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = emphasized ? 1 : 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        if emphasized {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.12
            layer?.shadowRadius = 10
            layer?.shadowOffset = NSSize(width: 0, height: -3)
        }
        alphaValue = preview == nil ? 0.28 : (emphasized ? 1 : 0.62)

        titleLabel.font = .systemFont(ofSize: emphasized ? 11 : 12, weight: .semibold)
        titleLabel.textColor = FocusStackTypeTabView.accent(for: preview)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .right
        contentLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentLabel.maximumNumberOfLines = 2
        contentLabel.lineBreakMode = .byTruncatingTail
        imageView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.stringValue = preview?.title ?? ""
        detailLabel.stringValue = preview?.detail ?? ""
        positionLabel.stringValue = position
        if let preview {
            switch preview.content {
            case let .text(value):
                contentLabel.stringValue = value
            case .image:
                imageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
                imageView.contentTintColor = .tertiaryLabelColor
            case let .files(names, remainingCount):
                let suffix = remainingCount > 0 ? "  +\(remainingCount)" : ""
                contentLabel.stringValue = names.joined(separator: "   ") + suffix
            case .metadata:
                break
            }
        }
        for child in [titleLabel, detailLabel, positionLabel, contentLabel, imageView] {
            addSubview(child)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = emphasized ? 14 : 12
        let available = bounds.width - inset * 2
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 27, width: available - 70, height: 16)
        positionLabel.frame = NSRect(x: bounds.width - inset - 66, y: bounds.height - 27, width: 66, height: 16)
        guard emphasized else { return }
        contentLabel.frame = NSRect(x: inset, y: 29, width: available, height: 38)
        imageView.frame = NSRect(x: inset, y: 27, width: available, height: 42)
        detailLabel.frame = NSRect(x: inset, y: 10, width: available, height: 15)
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        imageView.contentTintColor = nil
    }
}
