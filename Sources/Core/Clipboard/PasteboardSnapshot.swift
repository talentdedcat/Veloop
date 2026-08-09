import Foundation

enum CaptureStatus: String, Codable, Equatable {
    case complete
    case partial
    case rejectedOversize
}

struct PasteboardSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let changeCount: Int
    let items: [PasteboardItemSnapshot]
    let totalStoredBytes: UInt64
    let captureStatus: CaptureStatus
    let contentHash: String

    init(
        id: UUID,
        createdAt: Date,
        changeCount: Int,
        items: [PasteboardItemSnapshot],
        captureStatus: CaptureStatus
    ) {
        self.id = id
        self.createdAt = createdAt
        self.changeCount = changeCount
        self.items = items
        self.totalStoredBytes = items.reduce(0) { itemTotal, item in
            let representationBytes = item.representations.reduce(0) { $0 + $1.byteCount }
            let fileBytes = item.fileSnapshots.reduce(0) { $0 + $1.byteCount }
            return itemTotal + representationBytes + fileBytes
        }
        self.captureStatus = captureStatus
        self.contentHash = ContentHash.snapshot(items: items)
    }
}
