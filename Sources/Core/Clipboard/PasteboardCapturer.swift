import AppKit
import Foundation
import UniformTypeIdentifiers

protocol PasteboardItemDataSource {
    var typeIdentifiers: [String] { get }
    func data(forTypeIdentifier typeIdentifier: String) -> Data?
}

struct NSPasteboardItemDataSource: PasteboardItemDataSource {
    let item: NSPasteboardItem

    var typeIdentifiers: [String] {
        item.types.map(\.rawValue)
    }

    func data(forTypeIdentifier typeIdentifier: String) -> Data? {
        item.data(forType: NSPasteboard.PasteboardType(typeIdentifier))
    }
}

enum CaptureOutcome: Equatable {
    case captured(PasteboardSnapshot)
    case skipped(CaptureSkipReason)
    case rejectedOversize(UInt64)
    case empty

    var snapshot: PasteboardSnapshot? {
        if case let .captured(snapshot) = self {
            return snapshot
        }
        return nil
    }
}

protocol PasteboardCapturing: AnyObject {
    func capture(_ pasteboard: NSPasteboard) throws -> CaptureOutcome
    func discardFileSnapshots(for snapshotID: UUID)
}

final class PasteboardCapturer: PasteboardCapturing {
    private let blobStore: BlobStore
    private let fileStore: FileSnapshotStore
    private let policy: PasteboardCapturePolicy
    private let limitLock = NSLock()
    private var maximumSingleSnapshotBytes: UInt64

    init(
        blobStore: BlobStore,
        fileStore: FileSnapshotStore,
        policy: PasteboardCapturePolicy,
        maximumSingleSnapshotBytes: UInt64
    ) {
        self.blobStore = blobStore
        self.fileStore = fileStore
        self.policy = policy
        self.maximumSingleSnapshotBytes = maximumSingleSnapshotBytes
    }

    func updateMaximumSingleSnapshotBytes(_ value: UInt64) {
        limitLock.lock()
        maximumSingleSnapshotBytes = value
        limitLock.unlock()
    }

    func capture(
        changeCount: Int,
        items: [PasteboardItemDataSource],
        snapshotID: UUID = UUID(),
        createdAt: Date = Date()
    ) throws -> CaptureOutcome {
        guard !items.isEmpty else {
            return .empty
        }
        let allTypes = items.flatMap(\.typeIdentifiers)
        if case let .skip(reason) = policy.decision(for: allTypes) {
            return .skipped(reason)
        }

        limitLock.lock()
        let byteLimit = maximumSingleSnapshotBytes
        limitLock.unlock()
        var retainFileSnapshots = false
        defer {
            if !retainFileSnapshots {
                try? fileStore.removeSnapshot(snapshotID)
            }
        }

        var storedBytes: UInt64 = 0
        var itemSnapshots: [PasteboardItemSnapshot] = []
        var partial = false

        for (itemIndex, item) in items.enumerated() {
            var representations: [PasteboardRepresentation] = []
            var fileSnapshots: [FileSnapshotReference] = []
            var copiedURLs: Set<String> = []

            for typeIdentifier in item.typeIdentifiers {
                guard let data = item.data(forTypeIdentifier: typeIdentifier) else {
                    representations.append(PasteboardRepresentation(
                        typeIdentifier: typeIdentifier,
                        blobHash: nil,
                        byteCount: 0,
                        status: .readFailed,
                        errorIdentifier: "data-unavailable"
                    ))
                    partial = true
                    continue
                }

                let (updatedStoredBytes, overflow) = storedBytes.addingReportingOverflow(UInt64(data.count))
                guard !overflow, updatedStoredBytes <= byteLimit else {
                    return .rejectedOversize(overflow ? .max : updatedStoredBytes)
                }
                storedBytes = updatedStoredBytes
                let blob = try blobStore.put(data)
                representations.append(PasteboardRepresentation(
                    typeIdentifier: typeIdentifier,
                    blobHash: blob.hash,
                    byteCount: blob.byteCount,
                    status: .stored,
                    errorIdentifier: nil
                ))

                guard isFileURLType(typeIdentifier),
                      let fileURL = materializedFileURL(from: data),
                      copiedURLs.insert(fileURL.standardizedFileURL.path).inserted else {
                    continue
                }
                let fileSnapshot = fileStore.snapshot(
                    sourceURL: fileURL,
                    snapshotID: snapshotID,
                    itemIndex: itemIndex,
                    ordinal: fileSnapshots.count,
                    typeIdentifier: typeIdentifier,
                    maximumBytes: byteLimit - storedBytes
                )
                if fileSnapshot.status == .tooLarge {
                    let (rejectedBytes, overflow) = storedBytes.addingReportingOverflow(fileSnapshot.byteCount)
                    return .rejectedOversize(overflow ? .max : rejectedBytes)
                }
                fileSnapshots.append(fileSnapshot)
                let (storedBytesIncludingFile, fileByteCountOverflow) = storedBytes.addingReportingOverflow(fileSnapshot.byteCount)
                guard !fileByteCountOverflow else {
                    return .rejectedOversize(.max)
                }
                storedBytes = storedBytesIncludingFile
                if fileSnapshot.status != .copied {
                    partial = true
                }
            }
            itemSnapshots.append(PasteboardItemSnapshot(
                index: itemIndex,
                representations: representations,
                fileSnapshots: fileSnapshots
            ))
        }

        let snapshot = PasteboardSnapshot(
            id: snapshotID,
            createdAt: createdAt,
            changeCount: changeCount,
            items: itemSnapshots,
            captureStatus: partial ? .partial : .complete
        )
        retainFileSnapshots = true
        return .captured(snapshot)
    }

    func capture(_ pasteboard: NSPasteboard) throws -> CaptureOutcome {
        let items = (pasteboard.pasteboardItems ?? []).map(NSPasteboardItemDataSource.init)
        return try capture(changeCount: pasteboard.changeCount, items: items)
    }

    func discardFileSnapshots(for snapshotID: UUID) {
        try? fileStore.removeSnapshot(snapshotID)
    }

    private func isFileURLType(_ typeIdentifier: String) -> Bool {
        guard let type = UTType(typeIdentifier) else {
            return typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue
        }
        return type.conforms(to: .fileURL)
    }

    private func materializedFileURL(from data: Data) -> URL? {
        if let value = String(data: data, encoding: .utf8), let url = URL(string: value), url.isFileURL {
            return url
        }
        if let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let value = propertyList as? String,
           let url = URL(string: value),
           url.isFileURL {
            return url
        }
        return nil
    }
}
