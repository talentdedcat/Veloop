import Foundation

enum SnapshotRepositoryError: Error, Equatable {
    case missingBlob(String)
    case corruptedBlob(String)
}

struct SnapshotRepository {
    let blobStore: BlobStore

    func validate(_ snapshot: PasteboardSnapshot) throws {
        for item in snapshot.items {
            for representation in item.representations where representation.status == .stored {
                guard let hash = representation.blobHash else {
                    throw SnapshotRepositoryError.missingBlob("unidentified")
                }
                do {
                    guard try blobStore.validate(hash) else {
                        throw SnapshotRepositoryError.missingBlob(hash)
                    }
                } catch let error as BlobStoreError {
                    switch error {
                    case .missing:
                        throw SnapshotRepositoryError.missingBlob(hash)
                    case .invalidIdentifier, .corrupted:
                        throw SnapshotRepositoryError.corruptedBlob(hash)
                    }
                }
            }
        }
    }
}
