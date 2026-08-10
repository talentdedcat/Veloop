import Foundation

public struct PermissionIdentityReceipt: Codable, Equatable, Sendable {
    public let executableSHA256: String

    public init(executableSHA256: String) {
        self.executableSHA256 = executableSHA256
    }
}

public struct PermissionIdentityMigrator: @unchecked Sendable {
    public typealias Cleanup = @Sendable () throws -> Void

    private let executableURL: URL
    private let receiptURL: URL
    private let cleanup: Cleanup

    public init(
        executableURL: URL,
        receiptURL: URL,
        cleanup: @escaping Cleanup
    ) {
        self.executableURL = executableURL
        self.receiptURL = receiptURL
        self.cleanup = cleanup
    }

    public func migrateIfNeeded() throws {
        let executableData = try Data(contentsOf: executableURL)
        let currentHash = ContentHash.sha256(executableData)
        if let receipt = try? JSONDecoder().decode(
            PermissionIdentityReceipt.self,
            from: Data(contentsOf: receiptURL)
        ), receipt.executableSHA256 == currentHash {
            return
        }

        try cleanup()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            PermissionIdentityReceipt(executableSHA256: currentHash)
        )
        try AtomicFileWriter.replace(data, at: receiptURL)
    }
}
