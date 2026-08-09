import Foundation

struct PasteboardItemSnapshot: Codable, Equatable {
    let index: Int
    let representations: [PasteboardRepresentation]
    let fileSnapshots: [FileSnapshotReference]

    init(
        index: Int,
        representations: [PasteboardRepresentation],
        fileSnapshots: [FileSnapshotReference] = []
    ) {
        self.index = index
        self.representations = representations
        self.fileSnapshots = fileSnapshots
    }
}
