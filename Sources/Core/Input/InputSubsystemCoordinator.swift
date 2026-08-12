import Foundation

final class InputSubsystemCoordinator {
    private enum State {
        case unknown
        case running
        case stopped
    }

    private let startListening: () -> Bool
    private let stopListening: () -> Void
    private let activatePalette: () -> Task<Void, Never>
    private let deactivatePalette: () -> Void
    private var state = State.unknown
    private var activationTask: Task<Void, Never>?

    init(
        startListening: @escaping () -> Bool,
        stopListening: @escaping () -> Void,
        activatePalette: @escaping () -> Task<Void, Never>,
        deactivatePalette: @escaping () -> Void
    ) {
        self.startListening = startListening
        self.stopListening = stopListening
        self.activatePalette = activatePalette
        self.deactivatePalette = deactivatePalette
    }

    func synchronize(enabled: Bool, accessibility: Bool) {
        precondition(Thread.isMainThread)
        guard enabled && accessibility else {
            transitionToStopped()
            return
        }
        guard state != .running else { return }
        guard startListening() else {
            transitionToStopped()
            return
        }
        state = .running
        activationTask = activatePalette()
    }

    func stop() {
        precondition(Thread.isMainThread)
        transitionToStopped()
    }

    func listenerStoppedUnexpectedly() {
        precondition(Thread.isMainThread)
        guard state == .running else { return }
        activationTask?.cancel()
        activationTask = nil
        deactivatePalette()
        state = .stopped
    }

    private func transitionToStopped() {
        guard state != .stopped else { return }
        activationTask?.cancel()
        activationTask = nil
        stopListening()
        deactivatePalette()
        state = .stopped
    }
}
