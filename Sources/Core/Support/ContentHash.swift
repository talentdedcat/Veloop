import CryptoKit
import Foundation

enum ContentHash {
    static func isValidSHA256Identifier(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func snapshot(items: [PasteboardItemSnapshot]) -> String {
        var framed = Data()
        append(UInt64(items.count), to: &framed)

        for item in items {
            append(Int64(item.index), to: &framed)
            append(UInt64(item.representations.count), to: &framed)
            for representation in item.representations {
                append(representation.typeIdentifier, to: &framed)
                append(representation.blobHash ?? "", to: &framed)
                append(representation.byteCount, to: &framed)
                append(representation.status.rawValue, to: &framed)
                append(representation.errorIdentifier ?? "", to: &framed)
            }

            append(UInt64(item.fileSnapshots.count), to: &framed)
            for file in item.fileSnapshots {
                append(Int64(file.itemIndex), to: &framed)
                append(Int64(file.ordinal), to: &framed)
                append(file.originalTypeIdentifier, to: &framed)
                append(file.contentHash ?? "", to: &framed)
                append(file.byteCount, to: &framed)
                append(file.isDirectory ? UInt64(1) : UInt64(0), to: &framed)
                append(file.status.rawValue, to: &framed)
                append(file.errorIdentifier ?? "", to: &framed)
            }
        }

        return sha256(framed)
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        append(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func append(_ value: Int64, to data: inout Data) {
        append(UInt64(bitPattern: value), to: &data)
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
