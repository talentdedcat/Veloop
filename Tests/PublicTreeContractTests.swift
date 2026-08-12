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
        XCTAssertFalse(gitignoreRules.contains("Tests/"))
        XCTAssertFalse(gitignoreRules.contains("Tests/*.swift"))
        XCTAssertFalse(gitignoreRules.contains("*.swift"))
        XCTAssertTrue(gitignoreRules.contains("*.xcresult"))
        XCTAssertTrue(gitignoreRules.contains("*.xctest/"))
        XCTAssertTrue(gitignoreRules.contains("*.xctestrun"))

        for path in [
            "Sources/Core/Configuration/Configuration.swift",
            "Sources/Core/Configuration/ConfigurationStore.swift",
            "Configuration/VeloopApp-Info.plist",
            "Configuration/VeloopPalette-Info.plist",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
                "\(path) must exist in the public tree"
            )
        }

        for obsoletePath in [
            "Configuration/VeloopAgent-Info.plist",
            "Sources/Agent",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(obsoletePath).path),
                "\(obsoletePath) must not remain in the public tree"
            )
        }
    }
}
