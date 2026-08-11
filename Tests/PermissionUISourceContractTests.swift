import Foundation
import XCTest

final class PermissionUISourceContractTests: XCTestCase {
    func testTrashCleanupSettingHasExactlyTwoLocalizedChoices() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let english = try text("Sources/App/en.lproj/Localizable.strings")
        let chinese = try text("Sources/App/zh-Hans.lproj/Localizable.strings")

        XCTAssertTrue(controller.contains("NSSegmentedControl(labels:"))
        XCTAssertTrue(controller.contains("localization.string(\"trash.preserve\")"))
        XCTAssertTrue(controller.contains("localization.string(\"trash.purge\")"))
        XCTAssertTrue(controller.contains("trashCleanupControl.segmentCount == 2"))
        XCTAssertTrue(controller.contains("trashCleanupStore.policy ="))
        for key in ["trash.title", "trash.preserve", "trash.purge"] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), "English is missing \(key)")
            XCTAssertTrue(chinese.contains("\"\(key)\" = "), "Chinese is missing \(key)")
        }
    }

    func testPermissionRowsRenderGroupedFourStateModelWithoutNilToFalseFallback() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let render = try functionBody(named: "render", in: controller)
        let permissionRenderer = try functionBody(named: "renderPermission", in: controller)

        XCTAssertTrue(render.contains(
            "model.permissionSyncState.displayState(for: .inputMonitoring)"
        ))
        XCTAssertTrue(render.contains(
            "model.permissionSyncState.displayState(for: .accessibility)"
        ))
        XCTAssertNil(render.range(
            of: #"state\?\.permissions\.[^\n]+\?\? false"#,
            options: .regularExpression
        ))
        for state in ["checking", "allowed", "missing", "unavailable"] {
            XCTAssertTrue(permissionRenderer.contains("case .\(state):"), "Missing \(state) rendering")
        }
        XCTAssertTrue(permissionRenderer.contains("permissions.allowed"))
        XCTAssertTrue(permissionRenderer.contains("permissions.checking"))
        XCTAssertTrue(permissionRenderer.contains("permissions.missing"))
        XCTAssertTrue(permissionRenderer.contains("permissions.unavailable"))
    }

    func testUnavailableRenderingUsesAnErrorAppearanceDistinctFromMissing() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let permissionRenderer = try functionBody(named: "renderPermission", in: controller)
        let unavailable = try switchCase(named: "unavailable", in: permissionRenderer)
        let missing = try switchCase(named: "missing", in: permissionRenderer)

        XCTAssertTrue(unavailable.contains("permissions.unavailable"))
        XCTAssertTrue(unavailable.contains("xmark.octagon.fill"))
        XCTAssertTrue(unavailable.contains("systemRed"))
        XCTAssertTrue(missing.contains("permissions.missing"))
        XCTAssertTrue(missing.contains("exclamationmark.triangle.fill"))
        XCTAssertTrue(missing.contains("systemOrange"))
    }

    func testPermissionButtonsRemainAvailableOutsideLoadingState() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let render = try functionBody(named: "render", in: controller)

        XCTAssertTrue(render.contains(
            "inputSettingsButton.isEnabled = !model.isLoading"
        ))
        XCTAssertTrue(render.contains(
            "accessibilitySettingsButton.isEnabled = !model.isLoading"
        ))
    }

    func testSettingsActionsUseOneGatedGroupedRequestHelper() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let inputAction = try functionBody(named: "openInputSettings", in: controller)
        let accessibilityAction = try functionBody(named: "openAccessibilitySettings", in: controller)
        let helper = try functionBody(named: "openSystemSettings", in: controller)

        XCTAssertTrue(inputAction.contains(
            "openSystemSettings(\"Privacy_ListenEvent\", permissionGroup: .inputMonitoring)"
        ))
        XCTAssertTrue(accessibilityAction.contains(
            "openSystemSettings(\"Privacy_Accessibility\", permissionGroup: .accessibility)"
        ))
        let snapshot = try XCTUnwrap(helper.range(of:
            "let displayState = model.permissionSyncState.displayState(for: permissionGroup)"
        ))
        let open = try XCTUnwrap(helper.range(of: "NSWorkspace.shared.open(url)"))
        let gate = try XCTUnwrap(helper.range(of:
            "guard displayState == .missing else { return }"
        ))
        let request = try XCTUnwrap(helper.range(of:
            "Task { await model.requestPermissions(permissionGroup) }"
        ))

        XCTAssertLessThan(snapshot.lowerBound, open.lowerBound)
        XCTAssertLessThan(open.lowerBound, gate.lowerBound)
        XCTAssertLessThan(open.lowerBound, request.lowerBound)
        XCTAssertEqual(controller.components(separatedBy: "model.requestPermissions(").count - 1, 1)
        XCTAssertFalse(try functionBody(named: "render", in: controller).contains("requestPermissions"))
    }

    func testPermissionPresentationKeysAreSynchronizedAcrossLocalizations() throws {
        let english = try text("Sources/App/en.lproj/Localizable.strings")
        let chinese = try text("Sources/App/zh-Hans.lproj/Localizable.strings")

        for key in ["permissions.allowed", "permissions.missing", "permissions.checking", "permissions.unavailable"] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), "English is missing \(key)")
            XCTAssertTrue(chinese.contains("\"\(key)\" = "), "Chinese is missing \(key)")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func functionBody(named name: String, in source: String) throws -> Substring {
        try bracedBody(after: "func \(name)", in: source)
    }

    private func switchCase(named name: String, in source: Substring) throws -> Substring {
        let marker = try XCTUnwrap(source.range(of: "case .\(name):"))
        let suffix = source[marker.lowerBound...]
        guard let nextCase = suffix.dropFirst().range(of: "case .") else { return suffix }
        return source[marker.lowerBound..<nextCase.lowerBound]
    }

    private func bracedBody(after marker: String, in source: String) throws -> Substring {
        let markerRange = try XCTUnwrap(source.range(of: marker), "Missing \(marker)")
        let open = try XCTUnwrap(
            source[markerRange.upperBound...].firstIndex(of: "{"),
            "Missing opening brace after \(marker)"
        )
        var depth = 0
        var index = open
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[open...index] }
            default:
                break
            }
            index = source.index(after: index)
        }
        XCTFail("Missing closing brace after \(marker)")
        return source[open...]
    }
}
