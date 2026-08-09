import AppKit
import Foundation

protocol PreviewBlobReading: AnyObject {
    func data(for hash: String) throws -> Data
}

extension BlobStore: PreviewBlobReading {}

final class PastePreviewBuilder {
    private static let plainTextTypes = [
        "public.utf8-plain-text",
        "public.plain-text",
        "public.text",
        "NSStringPboardType",
    ]
    private static let richTextTypes: [(String, NSAttributedString.DocumentType)] = [
        ("public.rtf", .rtf),
        ("public.html", .html),
    ]
    private static let imageTypes = Set([
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.heic",
        "com.compuserve.gif",
        "public.svg-image",
    ])

    private let blobReader: PreviewBlobReading
    private let language: () -> AppLanguage

    init(
        blobReader: PreviewBlobReading,
        language: @escaping () -> AppLanguage = { .english }
    ) {
        self.blobReader = blobReader
        self.language = language
    }

    func build(snapshot: PasteboardSnapshot, showContent: Bool) throws -> PastePreview {
        guard showContent else {
            return metadataPreview(for: snapshot)
        }

        if let text = try plainText(in: snapshot) {
            return PastePreview(
                id: snapshot.id,
                title: localized("Text", "文本"),
                detail: detail(for: snapshot),
                content: .text(Self.bounded(text))
            )
        }
        if let text = try richText(in: snapshot) {
            return PastePreview(
                id: snapshot.id,
                title: localized("Rich Text", "富文本"),
                detail: detail(for: snapshot),
                content: .text(Self.bounded(text))
            )
        }
        if let hash = imageHash(in: snapshot) {
            return PastePreview(
                id: snapshot.id,
                title: localized("Image", "图像"),
                detail: detail(for: snapshot),
                content: .image(blobHash: hash)
            )
        }

        let fileNames = snapshot.items
            .flatMap(\.fileSnapshots)
            .filter { $0.status == .copied }
            .compactMap { reference -> String? in
                guard let path = reference.relativePath else { return nil }
                return URL(fileURLWithPath: path).lastPathComponent
            }
        if !fileNames.isEmpty {
            return PastePreview(
                id: snapshot.id,
                title: localized(fileNames.count == 1 ? "File" : "Files", "文件"),
                detail: detail(for: snapshot),
                content: .files(
                    names: Array(fileNames.prefix(3)),
                    remainingCount: max(0, fileNames.count - 3)
                )
            )
        }
        return metadataPreview(for: snapshot)
    }

    func buildType(snapshot: PasteboardSnapshot) -> PastePreview {
        let storedTypes = Set(snapshot.items
            .flatMap(\.representations)
            .filter { $0.status == .stored }
            .map(\.typeIdentifier))
        let title: String
        let content: PastePreviewContent
        if Self.plainTextTypes.contains(where: storedTypes.contains)
            || Self.richTextTypes.contains(where: { storedTypes.contains($0.0) }) {
            title = localized("Text", "文本")
            content = .text("")
        } else if !storedTypes.isDisjoint(with: Self.imageTypes) {
            title = localized("Image", "图像")
            content = .image(blobHash: "")
        } else if snapshot.items.contains(where: { !$0.fileSnapshots.isEmpty }) {
            title = localized("File", "文件")
            content = .files(names: [], remainingCount: 0)
        } else {
            title = localized("Clipboard Data", "剪贴板数据")
            content = .metadata
        }
        return PastePreview(id: snapshot.id, title: title, detail: "", content: content)
    }

    private func plainText(in snapshot: PasteboardSnapshot) throws -> String? {
        for type in Self.plainTextTypes {
            guard let representation = storedRepresentation(type: type, in: snapshot),
                  let hash = representation.blobHash else { continue }
            let data = try blobReader.data(for: hash)
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    private func richText(in snapshot: PasteboardSnapshot) throws -> String? {
        for (type, documentType) in Self.richTextTypes {
            guard let representation = storedRepresentation(type: type, in: snapshot),
                  let hash = representation.blobHash else { continue }
            let data = try blobReader.data(for: hash)
            if let value = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            ), !value.string.isEmpty {
                return value.string
            }
        }
        return nil
    }

    private func imageHash(in snapshot: PasteboardSnapshot) -> String? {
        snapshot.items.lazy
            .flatMap(\.representations)
            .first(where: {
                $0.status == .stored
                    && Self.imageTypes.contains($0.typeIdentifier)
                    && $0.blobHash != nil
            })?.blobHash
    }

    private func storedRepresentation(
        type: String,
        in snapshot: PasteboardSnapshot
    ) -> PasteboardRepresentation? {
        snapshot.items.lazy
            .flatMap(\.representations)
            .first { $0.typeIdentifier == type && $0.status == .stored && $0.blobHash != nil }
    }

    private func metadataPreview(for snapshot: PasteboardSnapshot) -> PastePreview {
        let firstType = snapshot.items.lazy
            .flatMap(\.representations)
            .first?.typeIdentifier ?? "clipboard"
        return PastePreview(
            id: snapshot.id,
            title: localized("Clipboard Data", "剪贴板数据"),
            detail: "\(firstType) · \(Self.formatBytes(snapshot.totalStoredBytes))",
            content: .metadata
        )
    }

    private func detail(for snapshot: PasteboardSnapshot) -> String {
        let itemCount = localized(
            "\(snapshot.items.count) item\(snapshot.items.count == 1 ? "" : "s")",
            "\(snapshot.items.count) 项"
        )
        return "\(itemCount) · \(Self.formatBytes(snapshot.totalStoredBytes))"
    }

    private func localized(_ english: String, _ simplifiedChinese: String) -> String {
        let selected = language()
        let usesChinese = selected == .simplifiedChinese
            || (selected == .system && Locale.preferredLanguages.first?.hasPrefix("zh-Hans") == true)
        return usesChinese ? simplifiedChinese : english
    }

    private static func bounded(_ value: String) -> String {
        let lineBounded = value.components(separatedBy: .newlines).prefix(3).joined(separator: "\n")
        let wasTruncated = lineBounded != value || lineBounded.unicodeScalars.count > 240
        guard wasTruncated else { return lineBounded }
        let prefix = lineBounded.unicodeScalars.prefix(239)
        return String(String.UnicodeScalarView(prefix)) + "…"
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1_024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
