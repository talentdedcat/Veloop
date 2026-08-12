import Foundation

enum GlobalInputEvent: Equatable {
    case commandV
    case vKeyUp
    case move(PasteCycleDirection)
    case navigationKeyUp
    case commandReleased
    case escape
    case other
}

final class PasteCycleController {
    private let lock = NSLock()
    private let historyIDs: () -> [UUID]
    private let canCycle: () -> Bool
    private let canContinueCycle: () -> Bool
    private let prepareCycle: ((@escaping ([UUID]?) -> Void) -> Void)?
    private let commitQueue: DispatchQueue
    private let present: (PasteCyclePresentationEvent) -> Void
    private let fallbackPaste: () -> Void
    private let commit: (UUID) -> Void
    private var state = PasteCycleState()
    private var preparationID: UUID?

    init(
        historyIDs: @escaping () -> [UUID],
        canCycle: @escaping () -> Bool,
        canContinueCycle: @escaping () -> Bool = { true },
        prepareCycle: ((@escaping ([UUID]?) -> Void) -> Void)? = nil,
        commitQueue: DispatchQueue = DispatchQueue(label: "com.veloop.paste-commit"),
        present: @escaping (PasteCyclePresentationEvent) -> Void = { _ in },
        fallbackPaste: @escaping () -> Void = {},
        commit: @escaping (UUID) -> Void
    ) {
        self.historyIDs = historyIDs
        self.canCycle = canCycle
        self.canContinueCycle = canContinueCycle
        self.prepareCycle = prepareCycle
        self.commitQueue = commitQueue
        self.present = present
        self.fallbackPaste = fallbackPaste
        self.commit = commit
    }

    var isCycling: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.phase == .cycling
    }

    func handle(_ event: GlobalInputEvent) -> Bool {
        var presentationEvent: PasteCyclePresentationEvent?
        var snapshotToCommit: UUID?
        var preparation: (id: UUID, run: (@escaping ([UUID]?) -> Void) -> Void)?
        var shouldFallbackPaste = false
        let shouldSuppress: Bool

        lock.lock()
        if (state.phase == .cycling || preparationID != nil) && !canContinueCycle() {
            shouldFallbackPaste = preparationID != nil
            presentationEvent = .interrupted
            preparationID = nil
            state.resetForInterruption()
            shouldSuppress = false
        } else {
            switch event {
        case .commandV:
            if preparationID != nil {
                shouldSuppress = true
                break
            }
            let wasCycling = state.phase == .cycling
            let ids: [UUID]
            if wasCycling {
                ids = []
            } else {
                guard canCycle() else {
                    state.resetForInterruption()
                    shouldSuppress = false
                    break
                }
                if let prepareCycle {
                    let id = UUID()
                    preparationID = id
                    preparation = (id, prepareCycle)
                    shouldSuppress = true
                    break
                }
                ids = historyIDs()
                guard !ids.isEmpty else {
                    state.resetForInterruption()
                    shouldSuppress = false
                    break
                }
            }
            let action = state.handle(.commandV, historyIDs: ids)
            shouldSuppress = action == .suppress
            if shouldSuppress, !wasCycling,
               let selection = state.selection(direction: .older) {
                presentationEvent = .selected(selection)
            }
        case let .move(direction):
            if preparationID != nil {
                shouldSuppress = true
                break
            }
            guard state.phase == .cycling else {
                shouldSuppress = false
                break
            }
            let selectedBeforeMove = state.selectedSnapshotID
            let action = state.handle(.move(direction), historyIDs: [])
            shouldSuppress = action == .suppress
            if shouldSuppress,
               state.selectedSnapshotID != selectedBeforeMove,
               let selection = state.selection(direction: direction) {
                presentationEvent = .selected(selection)
            }
        case .vKeyUp, .navigationKeyUp:
            shouldSuppress = state.phase == .cycling || preparationID != nil
        case .commandReleased:
            if preparationID != nil {
                preparationID = nil
                state.resetForInterruption()
                presentationEvent = .interrupted
                shouldFallbackPaste = true
                shouldSuppress = false
                break
            }
            let action = state.handle(.commandReleased, historyIDs: [])
            if case let .commit(snapshotID) = action {
                presentationEvent = .committing
                snapshotToCommit = snapshotID
            }
            shouldSuppress = false
        case .escape:
            if preparationID != nil {
                preparationID = nil
                state.resetForInterruption()
                presentationEvent = .cancelled
                shouldSuppress = true
                break
            }
            let action = state.handle(.escape, historyIDs: [])
            shouldSuppress = action == .cancel
            if shouldSuppress {
                presentationEvent = .cancelled
            }
        case .other:
            shouldSuppress = false
            }
        }
        lock.unlock()

        if let preparation {
            preparation.run { [weak self] ids in
                self?.finishPreparation(id: preparation.id, historyIDs: ids)
            }
        }
        if let presentationEvent {
            present(presentationEvent)
        }
        if shouldFallbackPaste {
            fallbackPaste()
        }
        if let snapshotToCommit {
            commitQueue.async { [commit] in
                commit(snapshotToCommit)
            }
        }
        return shouldSuppress
    }

    func interrupt() {
        lock.lock()
        let wasActive = state.phase == .cycling || preparationID != nil
        preparationID = nil
        state.resetForInterruption()
        lock.unlock()
        if wasActive {
            present(.interrupted)
        }
    }

    private func finishPreparation(id: UUID, historyIDs: [UUID]?) {
        var presentationEvent: PasteCyclePresentationEvent?
        var shouldFallbackPaste = false

        lock.lock()
        guard preparationID == id else {
            lock.unlock()
            return
        }
        preparationID = nil
        if let historyIDs, !historyIDs.isEmpty, canContinueCycle() {
            let action = state.handle(.commandV, historyIDs: historyIDs)
            if action == .suppress,
               let selection = state.selection(direction: .older) {
                presentationEvent = .selected(selection)
            }
        } else {
            state.resetForInterruption()
            presentationEvent = .interrupted
            shouldFallbackPaste = true
        }
        lock.unlock()

        if let presentationEvent {
            present(presentationEvent)
        }
        if shouldFallbackPaste {
            fallbackPaste()
        }
    }
}
