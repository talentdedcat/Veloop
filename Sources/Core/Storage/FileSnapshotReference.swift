import Foundation

enum FileSnapshotStatus: String, Codable, Equatable {
    case copied
    case copyFailed
    case sourceMissing
    case tooLarge
}

struct FileSnapshotReference: Codable, Equatable {
    let itemIndex: Int
    let ordinal: Int
    let originalTypeIdentifier: String
    let relativePath: String?
    let contentHash: String?
    let byteCount: UInt64
    let isDirectory: Bool
    let status: FileSnapshotStatus
    let errorIdentifier: String?
}
