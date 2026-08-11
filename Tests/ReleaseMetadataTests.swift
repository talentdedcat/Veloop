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
            "Veloop uses one permission identity and one display name",
            "No separate Veloop Agent.app is installed.",
            "show the Veloop logo in privacy lists",
            "old extensionless `AgentRuntime/Veloop` path",
            "path-based duplicate is not created again",
            "a changed ad-hoc binary has a new code hash",
            "clears stale Veloop permission records",
            "Re-enable Accessibility once after an ad-hoc binary update",
            "queries the healthy Agent first without restarting it",
            "Returning from System Settings force-restarts only the Agent before reading permission state",
            "never re-enables an Event Tap disabled by user input",
            "reports both directions accurately",
            "AgentRuntime/Veloop.app",
            "can be moved directly to Trash",
            "removes current and legacy Veloop permission records",
            "byte-for-byte preservation of `config.json` and `history.json`",
            "Preserve History and Settings",
            "Remove Everything",
            "always performs a complete purge",
            "Veloop never invokes the macOS permission prompt",
            "only opens the Accessibility pane in System Settings",
            "Accessibility is the only permission users need to enable",
            "verifies listening, posting, and Accessibility access separately",
            "queries the Palette first",
            "never asks macOS to enable the Palette input source",
            "focused Accessibility element",
            "does not traverse the Accessibility tree",
            "already-running applications do not need to reconnect to the Palette",
            "native text editors, chat input fields, code editors, browser address fields, and editable web content",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("reproducible public build"))
        XCTAssertFalse(readme.contains("<strong>Input Monitoring</strong>"))
        XCTAssertFalse(readme.contains("Re-enable both permissions"))
    }

    func testChineseReadmeDocumentsReleaseAndPermissionRecovery() throws {
        let readme = try text("Docs/README.zh-CN.md")

        for requiredText in [
            "release-v0.2.0",
            "Veloop-0.2.0-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            #"<table align="center">"#,
            "Veloop 只使用一个权限身份和一个显示名称",
            "不会安装独立的 Veloop Agent.app。",
            "显示 Veloop Logo",
            "旧的无后缀 `AgentRuntime/Veloop` 路径",
            "不会再产生这种路径型重复项",
            "ad-hoc 二进制发生变化时，代码哈希也会变化",
            "清除旧的 Veloop 权限记录",
            "ad-hoc 二进制更新后重新启用一次“辅助功能”",
            "优先查询健康的 Agent，不会先重启",
            "从“系统设置”返回 Veloop 时，会先仅重启 Agent",
            "绝不会重新启用因用户输入而被禁用的 Event Tap",
            "准确识别两个方向的变化",
            "AgentRuntime/Veloop.app",
            "直接移到废纸篓",
            "移除当前和旧版 Veloop 权限记录",
            "`config.json` 与 `history.json` 的内容哈希",
            "保留历史记录和设置",
            "移除所有内容",
            "始终执行彻底清理",
            "Veloop 绝不会主动调用 macOS 权限弹窗",
            "只会打开“系统设置”中的“辅助功能”页面",
            "用户只需开启“辅助功能”",
            "分别检查监听、事件发送和 Accessibility 访问能力",
            "首先查询 Palette",
            "绝不会请求 macOS 启用 Palette 输入源",
            "当前聚焦的 Accessibility 元素",
            "不会遍历 Accessibility 树",
            "已经运行的应用不需要重新连接 Palette",
            "原生文本编辑器、聊天输入框、代码编辑器、浏览器地址栏和网页可编辑区域",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("可复现的公开构建"))
        XCTAssertFalse(readme.contains("<strong>输入监控</strong>"))
        XCTAssertFalse(readme.contains("重新启用一次这两项权限"))
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
