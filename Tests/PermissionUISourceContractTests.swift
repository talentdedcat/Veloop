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

    func testSingleAccessibilityRowRendersCombinedFourStateModel() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let render = try functionBody(named: "render", in: controller)
        let permissionRenderer = try functionBody(named: "renderPermission", in: controller)

        XCTAssertTrue(render.contains(
            "model.permissionSyncState.displayState"
        ))
        XCTAssertFalse(render.contains("displayState(for:"))
        for obsolete in [
            "inputStatusImage",
            "inputStatusLabel",
            "inputSettingsButton",
            "inputPermissionLabel",
        ] {
            XCTAssertFalse(controller.contains(obsolete), obsolete)
        }
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

    func testAccessibilityButtonRemainsAvailableOutsideLoadingState() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let render = try functionBody(named: "render", in: controller)

        XCTAssertTrue(render.contains(
            "accessibilitySettingsButton.isEnabled = !model.isLoading"
        ))
        XCTAssertFalse(controller.contains("inputSettingsButton"))
    }

    func testOnlyAccessibilitySettingsActionRemains() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let accessibilityAction = try functionBody(named: "openAccessibilitySettings", in: controller)
        let helper = try functionBody(named: "openSystemSettings", in: controller)

        XCTAssertTrue(accessibilityAction.contains(
            "openSystemSettings(\"Privacy_Accessibility\")"
        ))
        XCTAssertTrue(helper.contains("NSWorkspace.shared.open(url)"))
        XCTAssertFalse(controller.contains("openInputSettings"))
        XCTAssertFalse(controller.contains("Privacy_ListenEvent"))
    }

    func testSubmittedLimitTextSynchronizesItsStepperImmediately() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let history = try functionBody(named: "historyLimitSubmitted", in: controller)
        let storage = try functionBody(named: "storageLimitSubmitted", in: controller)

        let historySync = try XCTUnwrap(history.range(of:
            "historyStepper.integerValue = count"
        ))
        let historyUpdate = try XCTUnwrap(history.range(of:
            "model.update(ControlUpdate(maximumHistoryCount: count))"
        ))
        XCTAssertLessThan(historySync.lowerBound, historyUpdate.lowerBound)

        let storageSync = try XCTUnwrap(storage.range(of:
            "storageStepper.integerValue = storageField.integerValue"
        ))
        let storageUpdate = try XCTUnwrap(storage.range(of:
            "model.update(ControlUpdate(maximumDiskBytes: bytes))"
        ))
        XCTAssertLessThan(storageSync.lowerBound, storageUpdate.lowerBound)
    }

    func testPermissionPresentationKeysAreSynchronizedAcrossLocalizations() throws {
        let english = try text("Sources/App/en.lproj/Localizable.strings")
        let chinese = try text("Sources/App/zh-Hans.lproj/Localizable.strings")

        for key in ["permissions.allowed", "permissions.missing", "permissions.checking", "permissions.unavailable"] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), "English is missing \(key)")
            XCTAssertTrue(chinese.contains("\"\(key)\" = "), "Chinese is missing \(key)")
        }
        XCTAssertFalse(english.contains("permissions.inputMonitoring"))
        XCTAssertFalse(chinese.contains("permissions.inputMonitoring"))
    }

    func testSinglePermissionRowUsesTighterFixedWindow() throws {
        let controller = try text("Sources/App/ControlViewController.swift")
        let window = try text("Sources/App/ControlWindowController.swift")

        XCTAssertTrue(controller.contains("outer.heightAnchor.constraint(equalToConstant: 408)"))
        XCTAssertTrue(window.contains("NSSize(width: 680, height: 460)"))
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
