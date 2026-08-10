import Foundation
@testable import VeloopCore
import XCTest

final class ReleaseMetadataTests: XCTestCase {
    func testPublicVersionIsZeroOneThree() {
        XCTAssertEqual(AppConstants.version, "0.1.3")
    }

    func testTrackedBundleMetadataUsesVersionZeroOneThreeAndBuildFour() throws {
        for path in [
            "Configuration/VeloopApp-Info.plist",
            "Configuration/VeloopAgent-Info.plist",
            "Configuration/VeloopPalette-Info.plist",
        ] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )

            XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.1.3", path)
            XCTAssertEqual(plist["CFBundleVersion"] as? String, "4", path)
        }
    }

    func testCaskUsesVersionZeroOneThreeAndRetainsARealChecksum() throws {
        let cask = try text("Casks/veloop.rb")
        XCTAssertTrue(cask.contains("version \"0.1.3\""))
        XCTAssertNotNil(
            cask.range(of: #"sha256 "[0-9a-f]{64}""#, options: .regularExpression)
        )
    }

    func testEnglishReadmeDocumentsReleaseAndPermissionRecovery() throws {
        let readme = try text("README.md")

        for requiredText in [
            "release-v0.1.3",
            "Veloop-0.1.3-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            #"<table align="center">"#,
            "Permission status is checked live by the background Agent.",
            #"“Checking” and “Agent unavailable” are distinct from “Missing.”"#,
            "On launch and whenever the control app becomes active, Veloop restarts the currently installed Agent and refreshes permission status.",
            "This also covers permission changes made by opening System Settings independently.",
            "An ordinary launch does not prompt for permissions.",
            "Use the permission buttons only when the corresponding permission is missing.",
            "an upgrade may require enabling Veloop again in System Settings",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("After returning from System Settings"))
        XCTAssertFalse(readme.contains("reproducible public build"))
    }

    func testChineseReadmeDocumentsReleaseAndPermissionRecovery() throws {
        let readme = try text("Docs/README.zh-CN.md")

        for requiredText in [
            "release-v0.1.3",
            "Veloop-0.1.3-universal.dmg",
            "brew install --cask Veloop",
            "xattr -dr com.apple.quarantine /Applications/Veloop.app",
            #"<table align="center">"#,
            "权限状态由后台 Agent 实时检查。",
            "“检查中”和“Agent 不可用”都不同于“缺失”。",
            "启动时以及控制应用每次重新激活时，Veloop 都会重启当前安装的 Agent 并刷新权限状态。",
            "这也涵盖用户自行打开“系统设置”所做的权限更改。",
            "普通启动不会请求权限。",
            "仅在相应权限缺失时使用权限按钮。",
            "升级后可能需要在“系统设置”中重新启用 Veloop",
        ] {
            XCTAssertTrue(readme.contains(requiredText), requiredText)
        }
        XCTAssertFalse(readme.contains("从“系统设置”返回后"))
        XCTAssertFalse(readme.contains("可复现的公开构建"))
    }

    func testSourceGuideDescribesOnlyTheStateRefreshAsBounded() throws {
        let sourceGuide = try text("Sources/README.md")

        XCTAssertTrue(sourceGuide.contains(
            "Launch and every control-app activation trigger an Agent restart followed by a bounded state refresh"
        ))
        XCTAssertFalse(sourceGuide.contains("bounded Agent restart"))
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
