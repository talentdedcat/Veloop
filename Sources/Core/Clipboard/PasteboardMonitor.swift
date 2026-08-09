import AppKit
import Foundation

final class PasteboardMonitor {
    private let pasteboard: NSPasteboard
    private let capturer: PasteboardCapturing
    private let historyStore: HistoryStore
    private let transaction: RestorationTransaction
    private let intervalMilliseconds: Int
    private let timerQueue = DispatchQueue(
        label: "com.veloop.pasteboard-timer",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    private let captureQueue = DispatchQueue(
        label: "com.veloop.pasteboard-capture",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    private var timer: DispatchSourceTimer?
    private var lastHandledChangeCount: Int
    private var captureInFlight = false
    private var enabled = false

    init(
        pasteboard: NSPasteboard = .general,
        capturer: PasteboardCapturing,
        historyStore: HistoryStore,
        transaction: RestorationTransaction,
        pollIntervalMilliseconds: Int
    ) {
        self.pasteboard = pasteboard
        self.capturer = capturer
        self.historyStore = historyStore
        self.transaction = transaction
        self.intervalMilliseconds = pollIntervalMilliseconds
        self.lastHandledChangeCount = pasteboard.changeCount
    }

    func start() {
        precondition(Thread.isMainThread)
        guard timer == nil else {
            enabled = true
            return
        }
        enabled = true
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        let leewayMilliseconds = min(100, max(1, intervalMilliseconds / 4))
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMilliseconds),
            repeating: .milliseconds(intervalMilliseconds),
            leeway: .milliseconds(leewayMilliseconds)
        )
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.poll()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        if enabled, !self.enabled {
            lastHandledChangeCount = pasteboard.changeCount
        }
        self.enabled = enabled
    }

    func stop() {
        precondition(Thread.isMainThread)
        enabled = false
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        captureQueue.sync {}
    }

    private func poll() {
        precondition(Thread.isMainThread)
        guard enabled, !captureInFlight else {
            return
        }
        let observedChangeCount = pasteboard.changeCount
        guard observedChangeCount != lastHandledChangeCount else {
            return
        }
        captureInFlight = true

        captureQueue.async { [weak self] in
            guard let self else {
                return
            }
            var handledChangeCount = observedChangeCount
            do {
                let outcome = try self.capturer.capture(self.pasteboard)
                if let snapshot = outcome.snapshot {
                    handledChangeCount = snapshot.changeCount
                    if self.transaction.consumeIfMatches(
                        changeCount: snapshot.changeCount,
                        contentHash: snapshot.contentHash
                    ) {
                        self.capturer.discardFileSnapshots(for: snapshot.id)
                    } else {
                        try self.historyStore.add(snapshot)
                    }
                } else if case .rejectedOversize = outcome {
                    try self.historyStore.garbageCollectUnreferencedBlobs()
                }
            } catch {
                try? self.historyStore.garbageCollectUnreferencedBlobs()
                handledChangeCount = self.pasteboard.changeCount
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastHandledChangeCount = handledChangeCount
                self.captureInFlight = false
                self.poll()
            }
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}
