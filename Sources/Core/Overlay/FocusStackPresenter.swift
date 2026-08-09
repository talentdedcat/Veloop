import AppKit
import Foundation

struct FocusStackFrame: Equatable {
    let newer: PastePreview?
    let selected: PastePreview
    let older: PastePreview?
    let position: Int
    let count: Int
    let direction: PasteCycleDirection
}

protocol FocusStackSurface: AnyObject {
    var isVisible: Bool { get }
    func show(frame: FocusStackFrame, at panelFrame: NSRect, animated: Bool)
    func hide(animated: Bool)
    func releaseTransientResources()
}

protocol FocusStackFrameBuilding: AnyObject {
    func build(
        selection: PasteCycleSelection,
        showContent: Bool,
        completion: @escaping (FocusStackFrame?) -> Void
    )
}

final class CyclePresentationRelay {
    private let handler: (PasteCyclePresentationEvent) -> Void
    private let schedule: (@escaping () -> Void) -> Void
    private let deliverTerminal: (@escaping () -> Void) -> Void
    private let lock = NSLock()
    private var pendingSelection: PasteCyclePresentationEvent?
    private var drainScheduled = false

    init(
        handler: @escaping (PasteCyclePresentationEvent) -> Void,
        schedule: @escaping (@escaping () -> Void) -> Void = { block in
            DispatchQueue.main.async(execute: block)
        },
        deliverTerminal: @escaping (@escaping () -> Void) -> Void = { block in
            if Thread.isMainThread {
                block()
            } else {
                DispatchQueue.main.sync(execute: block)
            }
        }
    ) {
        self.handler = handler
        self.schedule = schedule
        self.deliverTerminal = deliverTerminal
    }

    func publish(_ event: PasteCyclePresentationEvent) {
        if case .selected = event {
            enqueueSelection(event)
            return
        }

        lock.lock()
        pendingSelection = nil
        lock.unlock()
        deliverTerminal { [handler] in
            handler(event)
        }
    }

    private func enqueueSelection(_ event: PasteCyclePresentationEvent) {
        lock.lock()
        pendingSelection = event
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        lock.unlock()

        guard shouldSchedule else {
            return
        }
        schedule { [weak self] in
            self?.drain()
        }
    }

    private func drain() {
        lock.lock()
        let event = pendingSelection
        pendingSelection = nil
        drainScheduled = false
        lock.unlock()

        if let event {
            handler(event)
        }
    }
}

final class FocusStackPresenter {
    private let surface: FocusStackSurface
    private let frameBuilder: FocusStackFrameBuilding
    private let showContent: () -> Bool
    private let placement: () -> NSRect?
    private let deliver: (@escaping () -> Void) -> Void
    private var generation: UInt64 = 0

    init(
        surface: FocusStackSurface,
        frameBuilder: FocusStackFrameBuilding,
        showContent: @escaping () -> Bool,
        placement: @escaping () -> NSRect? = {
            FocusStackPlacementResolver(caretBounds: { nil })
                .frame(panelSize: FocusStackPanelSurface.size)
        },
        deliver: @escaping (@escaping () -> Void) -> Void = { block in
            DispatchQueue.main.async(execute: block)
        }
    ) {
        self.surface = surface
        self.frameBuilder = frameBuilder
        self.showContent = showContent
        self.placement = placement
        self.deliver = deliver
    }

    func handle(_ event: PasteCyclePresentationEvent) {
        switch event {
        case let .selected(selection):
            generation &+= 1
            let requestedGeneration = generation
            frameBuilder.build(selection: selection, showContent: showContent()) { [weak self] frame in
                self?.deliver { [weak self] in
                    guard let self,
                          self.generation == requestedGeneration,
                          let frame,
                          let panelFrame = self.placement() else {
                        return
                    }
                    self.surface.show(frame: frame, at: panelFrame, animated: self.surface.isVisible)
                }
            }
        case .cancelled, .committing, .interrupted:
            generation &+= 1
            surface.hide(animated: false)
            surface.releaseTransientResources()
        }
    }
}

final class FocusStackFrameBuilder: FocusStackFrameBuilding {
    private let previewBuilder: PastePreviewBuilder
    private let snapshot: (UUID) -> PasteboardSnapshot?
    private let acquireLease: (UUID) -> SnapshotLease?
    private let queue: DispatchQueue

    init(
        previewBuilder: PastePreviewBuilder,
        snapshot: @escaping (UUID) -> PasteboardSnapshot?,
        acquireLease: @escaping (UUID) -> SnapshotLease?,
        queue: DispatchQueue = DispatchQueue(
            label: "com.veloop.preview-build",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem
        )
    ) {
        self.previewBuilder = previewBuilder
        self.snapshot = snapshot
        self.acquireLease = acquireLease
        self.queue = queue
    }

    func build(
        selection: PasteCycleSelection,
        showContent: Bool,
        completion: @escaping (FocusStackFrame?) -> Void
    ) {
        guard let selectedLease = acquireLease(selection.selectedID) else {
            completion(nil)
            return
        }
        let neighborLeases = [selection.newerID, selection.olderID]
            .compactMap { $0 }
            .compactMap(acquireLease)
        let leases = [selectedLease] + neighborLeases

        queue.async { [previewBuilder, snapshot] in
            defer { leases.forEach { $0.release() } }
            guard let selectedSnapshot = snapshot(selection.selectedID),
                  let selected = try? previewBuilder.build(
                    snapshot: selectedSnapshot,
                    showContent: showContent
                  ) else {
                completion(nil)
                return
            }
            let newer = selection.newerID
                .flatMap(snapshot)
                .map(previewBuilder.buildType)
            let older = selection.olderID
                .flatMap(snapshot)
                .map(previewBuilder.buildType)
            completion(FocusStackFrame(
                newer: newer,
                selected: selected,
                older: older,
                position: selection.index + 1,
                count: selection.count,
                direction: selection.direction
            ))
        }
    }
}
