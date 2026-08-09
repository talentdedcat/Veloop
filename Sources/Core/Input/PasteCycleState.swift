import Foundation

enum PasteCyclePhase: Equatable {
    case idle
    case cycling
    case cancelled
    case committed
}

enum PasteCycleEvent: Equatable {
    case commandV
    case move(PasteCycleDirection)
    case commandReleased
    case escape
}

enum PasteCycleAction: Equatable {
    case passThrough
    case suppress
    case commit(UUID)
    case cancel
}

enum PasteCycleDirection: Equatable {
    case older
    case newer
}

struct PasteCycleSelection: Equatable {
    let selectedID: UUID
    let newerID: UUID?
    let olderID: UUID?
    let index: Int
    let count: Int
    let direction: PasteCycleDirection
}

enum PasteCyclePresentationEvent: Equatable {
    case selected(PasteCycleSelection)
    case cancelled
    case committing
    case interrupted
}

struct PasteCycleState {
    private(set) var phase: PasteCyclePhase = .idle
    private(set) var commandPressed = false
    private(set) var currentIndex: Int?
    private(set) var sessionSnapshotIDs: [UUID] = []

    var selectedSnapshotID: UUID? {
        guard let currentIndex, sessionSnapshotIDs.indices.contains(currentIndex) else {
            return nil
        }
        return sessionSnapshotIDs[currentIndex]
    }

    func selection(direction: PasteCycleDirection) -> PasteCycleSelection? {
        guard let currentIndex,
              sessionSnapshotIDs.indices.contains(currentIndex) else {
            return nil
        }
        return PasteCycleSelection(
            selectedID: sessionSnapshotIDs[currentIndex],
            newerID: currentIndex > 0 ? sessionSnapshotIDs[currentIndex - 1] : nil,
            olderID: currentIndex + 1 < sessionSnapshotIDs.count ? sessionSnapshotIDs[currentIndex + 1] : nil,
            index: currentIndex,
            count: sessionSnapshotIDs.count,
            direction: direction
        )
    }

    @discardableResult
    mutating func handle(_ event: PasteCycleEvent, historyIDs: [UUID]) -> PasteCycleAction {
        switch event {
        case .commandV:
            return handleCommandV(historyIDs: historyIDs)
        case let .move(direction):
            return move(direction)
        case .commandReleased:
            guard phase == .cycling, let selectedSnapshotID else {
                return .passThrough
            }
            phase = .committed
            let action = PasteCycleAction.commit(selectedSnapshotID)
            reset()
            return action
        case .escape:
            guard phase == .cycling else {
                return .passThrough
            }
            phase = .cancelled
            reset()
            return .cancel
        }
    }

    mutating func resetForInterruption() {
        reset()
    }

    private mutating func handleCommandV(historyIDs: [UUID]) -> PasteCycleAction {
        if phase == .idle {
            guard !historyIDs.isEmpty else {
                return .passThrough
            }
            phase = .cycling
            commandPressed = true
            sessionSnapshotIDs = historyIDs
            currentIndex = 0
            return .suppress
        }

        guard phase == .cycling else {
            return .passThrough
        }
        return .suppress
    }

    private mutating func move(_ direction: PasteCycleDirection) -> PasteCycleAction {
        guard phase == .cycling, let currentIndex, !sessionSnapshotIDs.isEmpty else {
            return .passThrough
        }
        switch direction {
        case .older:
            self.currentIndex = min(currentIndex + 1, sessionSnapshotIDs.count - 1)
        case .newer:
            self.currentIndex = max(currentIndex - 1, 0)
        }
        return .suppress
    }

    private mutating func reset() {
        phase = .idle
        commandPressed = false
        currentIndex = nil
        sessionSnapshotIDs = []
    }
}
