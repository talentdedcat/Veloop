import Foundation

enum PastePreviewContent: Equatable {
    case text(String)
    case image(blobHash: String)
    case files(names: [String], remainingCount: Int)
    case metadata
}

struct PastePreview: Equatable, Identifiable, CustomStringConvertible {
    let id: UUID
    let title: String
    let detail: String
    let content: PastePreviewContent

    var description: String {
        let kind: String
        switch content {
        case .text: kind = "text"
        case .image: kind = "image"
        case .files: kind = "files"
        case .metadata: kind = "metadata"
        }
        return "PastePreview(id: \(id), kind: \(kind))"
    }
}
