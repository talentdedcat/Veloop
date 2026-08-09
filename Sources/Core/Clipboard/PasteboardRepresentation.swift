import Foundation

enum RepresentationStatus: String, Codable, Equatable {
    case stored
    case readFailed
    case missingBlob
}

struct PasteboardRepresentation: Codable, Equatable {
    let typeIdentifier: String
    let blobHash: String?
    let byteCount: UInt64
    let status: RepresentationStatus
    let errorIdentifier: String?
}
