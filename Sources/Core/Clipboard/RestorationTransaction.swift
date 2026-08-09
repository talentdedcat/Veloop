import Foundation

final class RestorationTransaction {
    private struct CompletedTransaction {
        let id: UUID
        let changeCount: Int
        let contentHash: String
    }

    private let lock = NSLock()
    private var activeIDs: Set<UUID> = []
    private var completed: [CompletedTransaction] = []

    func begin() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        activeIDs.insert(id)
        return id
    }

    func complete(id: UUID, changeCount: Int, contentHash: String) {
        lock.lock()
        defer { lock.unlock() }
        guard activeIDs.remove(id) != nil else {
            return
        }
        completed.append(CompletedTransaction(id: id, changeCount: changeCount, contentHash: contentHash))
        if completed.count > 8 {
            completed.removeFirst(completed.count - 8)
        }
    }

    func cancel(id: UUID) {
        lock.lock()
        activeIDs.remove(id)
        lock.unlock()
    }

    func consumeIfMatches(changeCount: Int, contentHash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = completed.firstIndex(where: {
            $0.changeCount == changeCount && $0.contentHash == contentHash
        }) else {
            return false
        }
        completed.remove(at: index)
        return true
    }
}
