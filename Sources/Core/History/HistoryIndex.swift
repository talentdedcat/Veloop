import Foundation

struct HistoryIndex: Codable, Equatable {
    let version: Int
    var snapshots: [PasteboardSnapshot]

    static let empty = HistoryIndex(version: 1, snapshots: [])
}
