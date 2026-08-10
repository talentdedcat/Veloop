import Foundation
@testable import VeloopCore
import XCTest

final class ReleaseMetadataTests: XCTestCase {
    func testPublicVersionIsZeroTwoZero() {
        XCTAssertEqual(AppConstants.version, "0.2.0")
    }

    func testTrackedBundleMetadataUsesVersionZeroTwoZeroAndBuildFive() throws {
        for path in [
            "Configuration/VeloopApp-Info.plist",
            "Configuration/VeloopPalette-Info.plist",
        ] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )

            XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.2.0", path)
            XCTAssertEqual(plist["CFBundleVersion"] as? String, "5", path)
        }
    }

    func testCaskUsesVersionZeroTwoZeroAndRetainsARealChecksum() throws {
        let cask = try text("Casks/veloop.rb")
        XCTAssertTrue(cask.contains("version \"0.2.0\""))
        XCTAssertNotNil(
            cask.range(of: #"sha256 "[0-9a-f]{64}""#, options: .regularExpression)
        )
    }

    func testEnglishReadmeDocumentsReleaseAndPermissionRecovery() throws {
        let readme = try text("README.md")

        for requiredText in [
            "release-v0.2.0",
            "Veloop-0.2.0-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            #"<table align="center">"#,
            "Veloop.app is the only permission-bearing Veloop application.",
            "No separate Veloop Agent.app is installed.",
            "a changed ad-hoc binary has a new code hash",
            "clears stale Veloop permission records",
            "Re-enable both permissions once after an ad-hoc binary update",
            "queries the healthy Agent first without restarting it",
            "reflected as soon as the control app becomes active",
            "Preserve History and Settings",
            "Remove Everything",
            "always performs a complete purge",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("After returning from System Settings"))
        XCTAssertFalse(readme.contains("reproducible public build"))
    }

    func testChineseReadmeDocumentsReleaseAndPermissionRecovery() throws {
        let readme = try text("Docs/README.zh-CN.md")

        for requiredText in [
            "release-v0.2.0",
            "Veloop-0.2.0-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            #"<table align="center">"#,
            "Veloop.app 是唯一承载权限的 Veloop 应用。",
            "不会再安装独立的 Veloop Agent.app。",
            "ad-hoc 二进制发生变化时，代码哈希也会变化",
            "清除旧的 Veloop 权限记录",
            "ad-hoc 二进制更新后重新启用一次这两项权限",
            "优先查询健康的 Agent，不会先重启",
            "控制应用重新激活时立即反映",
            "保留历史记录和设置",
            "移除所有内容",
            "始终执行彻底清理",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("从“系统设置”返回后"))
        XCTAssertFalse(readme.contains("可复现的公开构建"))
    }

    func testSourceGuideDescribesSingleIdentityAndImmediateRefresh() throws {
        let sourceGuide = try text("Sources/README.md")

        XCTAssertTrue(sourceGuide.contains(
            "The same `Veloop` executable runs in `--agent` mode"
        ))
        XCTAssertTrue(sourceGuide.contains("one bounded state request before recovery"))
        XCTAssertFalse(sourceGuide.contains("copies the signed embedded Agent"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
