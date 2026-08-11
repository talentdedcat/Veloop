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

    func testEnglishReadmeDocumentsPublicReleaseContract() throws {
        let readme = try text("README.md")

        for requiredText in [
            "release-v0.2.0",
            "Veloop-0.2.0-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            "Accessibility is the only permission users need to enable",
            "No separate Input Monitoring setup is required",
            "Veloop does not trigger the macOS permission prompt",
            "current focused Accessibility element",
            "`Veloop.app` and its background process share one permission identity",
            "Preserve History and Settings",
            "Remove Everything",
            "brew uninstall --cask veloop",
            "veloopctl uninstall --purge",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("<strong>Input Monitoring</strong>"))
        XCTAssertFalse(readme.contains("Re-enable both permissions"))
        XCTAssertFalse(readme.contains("browser address fields"))
        XCTAssertFalse(readme.contains("veloopctl help"))
        XCTAssertFalse(readme.contains("Veloop Agent.app"))
    }

    func testChineseReadmeDocumentsPublicReleaseContract() throws {
        let readme = try text("Docs/README.zh-CN.md")

        for requiredText in [
            "release-v0.2.0",
            "Veloop-0.2.0-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            "用户只需开启“辅助功能”",
            "不需要单独开启“输入监控”",
            "Veloop 不会主动触发 macOS 权限弹窗",
            "当前聚焦的 Accessibility 元素",
            "`Veloop.app` 与它的后台进程共享唯一的权限身份",
            "保留历史记录和设置",
            "移除所有内容",
            "brew uninstall --cask veloop",
            "veloopctl uninstall --purge",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("<strong>输入监控</strong>"))
        XCTAssertFalse(readme.contains("重新启用一次这两项权限"))
        XCTAssertFalse(readme.contains("浏览器地址栏"))
        XCTAssertFalse(readme.contains("veloopctl help"))
        XCTAssertFalse(readme.contains("Veloop Agent.app"))
    }

    func testSourceGuideDescribesSingleIdentityAndImmediateRefresh() throws {
        let sourceGuide = try text("Sources/README.md")

        XCTAssertTrue(sourceGuide.contains(
            "The same signed `Veloop` executable runs in `--agent` mode"
        ))
        XCTAssertTrue(sourceGuide.contains("one bounded state request before recovery"))
        XCTAssertTrue(sourceGuide.contains("force-restarts the Agent before reading permission state after System Settings"))
        XCTAssertTrue(sourceGuide.contains("never re-enables a tap disabled by user input"))
        XCTAssertTrue(sourceGuide.contains("Accessibility is the only user-configured permission"))
        XCTAssertTrue(sourceGuide.contains("queries the Palette first"))
        XCTAssertTrue(sourceGuide.contains("never calls `TISEnableInputSource`"))
        XCTAssertTrue(sourceGuide.contains("focused Accessibility element"))
        XCTAssertTrue(sourceGuide.contains("does not request permission"))
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
