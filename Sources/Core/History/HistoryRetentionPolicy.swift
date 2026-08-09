import Foundation

enum HistoryStorageReference: Equatable {
    case blob(hash: String, byteCount: UInt64)
    case file(byteCount: UInt64)
}

struct HistoryRetentionPolicy {
    let maximumCount: Int
    let maximumDiskBytes: UInt64

    static func storageBytes(
        for snapshotIDs: [UUID],
        references: [UUID: [HistoryStorageReference]]
    ) -> UInt64 {
        var blobSizes: [String: UInt64] = [:]
        var fileBytes: UInt64 = 0
        for snapshotID in snapshotIDs {
            for reference in references[snapshotID, default: []] {
                switch reference {
                case let .blob(hash, byteCount):
                    blobSizes[hash] = byteCount
                case let .file(byteCount):
                    fileBytes += byteCount
                }
            }
        }
        return blobSizes.values.reduce(0, +) + fileBytes
    }
}
