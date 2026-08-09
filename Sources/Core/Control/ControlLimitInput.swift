import Foundation

public enum ControlLimitInput {
    public static let bytesPerMegabyte: UInt64 = 1_048_576
    public static let storageStepMegabytes: UInt64 = 1

    public static func historyCount(from text: String) -> Int? {
        guard let value = Int(trimmed(text)), value > 0 else { return nil }
        return value
    }

    public static func storageBytes(fromMegabytes text: String) -> UInt64? {
        guard let megabytes = UInt64(trimmed(text)), megabytes > 0 else { return nil }
        let (bytes, overflow) = megabytes.multipliedReportingOverflow(by: bytesPerMegabyte)
        return overflow ? nil : bytes
    }

    public static func megabyteText(for bytes: UInt64) -> String {
        let wholeMegabytes = bytes / bytesPerMegabyte
        let roundedUp = wholeMegabytes + (bytes % bytesPerMegabyte == 0 ? 0 : 1)
        return String(max(1, roundedUp))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
