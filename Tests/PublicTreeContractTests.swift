import Foundation
import XCTest

final class PublicTreeContractTests: XCTestCase {
    func testPublicConfigurationFilesAreTracked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gitignore = try String(
            contentsOf: root.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        let gitignoreRules = Set(
            gitignore.split(whereSeparator: { $0.isNewline }).map(String.init)
        )

        for rule in ["Configuration/", "Packaging/", "Veloop.xcodeproj/", ".github/workflows/"] {
            XCTAssertFalse(gitignoreRules.contains(rule), "\(rule) must not be publicly ignored")
        }
        XCTAssertTrue(gitignoreRules.contains("Package.swift"))

        for path in [
            "Sources/Core/Configuration/Configuration.swift",
            "Sources/Core/Configuration/ConfigurationStore.swift",
            "Configuration/VeloopAgent-Info.plist",
            "Configuration/VeloopApp-Info.plist",
            "Configuration/VeloopPalette-Info.plist",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must exist in the public tree"
            )
        }
    }
}
