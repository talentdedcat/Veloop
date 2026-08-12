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
    private let commitQueue: DispatchQueue
    private let present: (PasteCyclePresentationEvent) -> Void
    private let commit: (UUID) -> Void
    private var state = PasteCycleState()

    init(
        historyIDs: @escaping () -> [UUID],
        canCycle: @escaping () -> Bool,
        canContinueCycle: @escaping () -> Bool = { true },
        commitQueue: DispatchQueue = DispatchQueue(label: "com.veloop.paste-commit"),
        present: @escaping (PasteCyclePresentationEvent) -> Void = { _ in },
        commit: @escaping (UUID) -> Void
    ) {
        self.historyIDs = historyIDs
        self.canCycle = canCycle
        self.canContinueCycle = canContinueCycle
        self.commitQueue = commitQueue
        self.present = present
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
        let shouldSuppress: Bool

        lock.lock()
        if state.phase == .cycling && !canContinueCycle() {
            presentationEvent = .interrupted
            state.resetForInterruption()
            shouldSuppress = false
        } else {
            switch event {
        case .commandV:
            let wasCycling = state.phase == .cycling
            let ids: [UUID]
            if wasCycling {
                ids = []
            } else {
                ids = historyIDs()
                guard !ids.isEmpty, canCycle() else {
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
            shouldSuppress = state.phase == .cycling
        case .commandReleased:
            let action = state.handle(.commandReleased, historyIDs: [])
            if case let .commit(snapshotID) = action {
                presentationEvent = .committing
                snapshotToCommit = snapshotID
            }
            shouldSuppress = false
        case .escape:
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

        if let presentationEvent {
            present(presentationEvent)
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
        let wasCycling = state.phase == .cycling
        state.resetForInterruption()
        lock.unlock()
        if wasCycling {
            present(.interrupted)
        }
    }
}
