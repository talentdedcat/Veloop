import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "agent")

    static func lifecycle(_ status: String) {
        logger.info("Agent status=\(status, privacy: .public)")
    }

    static func capture(snapshotID: UUID, itemCount: Int, typeCount: Int, byteCount: UInt64, status: String) {
        logger.info(
            "Capture id=\(snapshotID.uuidString, privacy: .public) items=\(itemCount) types=\(typeCount) bytes=\(byteCount) status=\(status, privacy: .public)"
        )
    }

    static func failure(category: String, error: Error) {
        let errorType = String(reflecting: type(of: error))
        logger.error("Failure category=\(category, privacy: .public) type=\(errorType, privacy: .public)")
    }

    static func caret(_ status: String) {
        logger.info("Caret status=\(status, privacy: .public)")
    }
}
