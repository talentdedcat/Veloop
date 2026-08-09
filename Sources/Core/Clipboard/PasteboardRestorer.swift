import AppKit
import Foundation

struct RestorationReceipt: Equatable {
    let transactionID: UUID
    let changeCount: Int
    let materializedContentHash: String
}

enum PasteboardRestorerError: Error, Equatable {
    case missingBlob(String)
    case representationRejected(String)
    case pasteboardWriteFailed
}

final class PasteboardRestorer {
    private let blobStore: BlobStore
    private let fileStore: FileSnapshotStore
    private let transaction: RestorationTransaction

    init(blobStore: BlobStore, fileStore: FileSnapshotStore, transaction: RestorationTransaction) {
        self.blobStore = blobStore
        self.fileStore = fileStore
        self.transaction = transaction
    }

    func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) throws -> RestorationReceipt {
        let transactionID = transaction.begin()
        do {
            var pasteboardItems: [NSPasteboardItem] = []
            var materializedItems: [PasteboardItemSnapshot] = []

            for itemSnapshot in snapshot.items {
                let item = NSPasteboardItem()
                var materializedRepresentations: [PasteboardRepresentation] = []
                for representation in itemSnapshot.representations where representation.status == .stored {
                    guard let blobHash = representation.blobHash else {
                        throw PasteboardRestorerError.missingBlob("unidentified")
                    }
                    let originalData: Data
                    do {
                        originalData = try blobStore.data(for: blobHash)
                    } catch {
                        throw PasteboardRestorerError.missingBlob(blobHash)
                    }
                    let data = redirectedFileURLData(
                        for: representation.typeIdentifier,
                        originalData: originalData,
                        references: itemSnapshot.fileSnapshots
                    )
                    let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                    guard item.setData(data, forType: type) else {
                        throw PasteboardRestorerError.representationRejected(representation.typeIdentifier)
                    }
                    materializedRepresentations.append(PasteboardRepresentation(
                        typeIdentifier: representation.typeIdentifier,
                        blobHash: ContentHash.sha256(data),
                        byteCount: UInt64(data.count),
                        status: .stored,
                        errorIdentifier: nil
                    ))
                }
                pasteboardItems.append(item)
                materializedItems.append(PasteboardItemSnapshot(
                    index: itemSnapshot.index,
                    representations: materializedRepresentations,
                    fileSnapshots: itemSnapshot.fileSnapshots
                ))
            }

            pasteboard.clearContents()
            guard pasteboard.writeObjects(pasteboardItems) else {
                throw PasteboardRestorerError.pasteboardWriteFailed
            }
            let contentHash = postWriteContentHash(
                pasteboard: pasteboard,
                fileSnapshotsByItemIndex: Dictionary(
                    uniqueKeysWithValues: materializedItems.map { ($0.index, $0.fileSnapshots) }
                )
            )
            let receipt = RestorationReceipt(
                transactionID: transactionID,
                changeCount: pasteboard.changeCount,
                materializedContentHash: contentHash
            )
            transaction.complete(
                id: transactionID,
                changeCount: receipt.changeCount,
                contentHash: receipt.materializedContentHash
            )
            return receipt
        } catch {
            transaction.cancel(id: transactionID)
            throw error
        }
    }

    private func redirectedFileURLData(
        for typeIdentifier: String,
        originalData: Data,
        references: [FileSnapshotReference]
    ) -> Data {
        guard let reference = references.first(where: { $0.originalTypeIdentifier == typeIdentifier }),
              let url = fileStore.restoredURL(for: reference) else {
            return originalData
        }
        return Data(url.absoluteString.utf8)
    }

    private func postWriteContentHash(
        pasteboard: NSPasteboard,
        fileSnapshotsByItemIndex: [Int: [FileSnapshotReference]]
    ) -> String {
        let items = (pasteboard.pasteboardItems ?? []).enumerated().map { index, item in
            let representations = item.types.map { type in
                let data = item.data(forType: type)
                return PasteboardRepresentation(
                    typeIdentifier: type.rawValue,
                    blobHash: data.map(ContentHash.sha256),
                    byteCount: UInt64(data?.count ?? 0),
                    status: data == nil ? .readFailed : .stored,
                    errorIdentifier: data == nil ? "data-unavailable" : nil
                )
            }
            return PasteboardItemSnapshot(
                index: index,
                representations: representations,
                fileSnapshots: fileSnapshotsByItemIndex[index, default: []]
            )
        }
        return ContentHash.snapshot(items: items)
    }
}
