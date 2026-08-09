import AppKit
import CoreFoundation
import Foundation

protocol PaletteCaretQuerying: AnyObject {
    func query(target: CaretTarget) -> PaletteCaretResponse?
}

final class PaletteCaretClient: PaletteCaretQuerying {
    static let portName = "com.veloop.palette.caret-location"
    private static let maximumMessageBytes = 4_096

    private let sendTimeout: CFTimeInterval
    private let receiveTimeout: CFTimeInterval

    init(sendTimeout: CFTimeInterval = 0.01, receiveTimeout: CFTimeInterval = 0.04) {
        self.sendTimeout = sendTimeout
        self.receiveTimeout = receiveTimeout
    }

    func query(target: CaretTarget) -> PaletteCaretResponse? {
        guard let port = CFMessagePortCreateRemote(nil, Self.portName as CFString),
              let request = try? PropertyListSerialization.data(
                fromPropertyList: [
                    "bundleIdentifier": target.bundleIdentifier,
                    "processIdentifier": Int(target.processIdentifier),
                ],
                format: .binary,
                options: 0
              ) else {
            return nil
        }

        var unmanagedResponse: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port,
            1,
            request as CFData,
            sendTimeout,
            receiveTimeout,
            CFRunLoopMode.defaultMode.rawValue,
            &unmanagedResponse
        )
        guard status == kCFMessagePortSuccess,
              let responseData = unmanagedResponse?.takeRetainedValue() as Data?,
              responseData.count <= Self.maximumMessageBytes,
              let response = try? PropertyListSerialization.propertyList(
                from: responseData,
                options: [],
                format: nil
              ) as? [String: Any],
              response["bundleIdentifier"] as? String == target.bundleIdentifier,
              let responseProcessIdentifier = (response["processIdentifier"] as? NSNumber)?.int32Value,
              responseProcessIdentifier == target.processIdentifier,
              let x = response["x"] as? NSNumber,
              let y = response["y"] as? NSNumber,
              let width = response["width"] as? NSNumber,
              let height = response["height"] as? NSNumber,
              let sourceValue = response["source"] as? String,
              let source = CaretSource(rawValue: sourceValue) else {
            return nil
        }

        return PaletteCaretResponse(
            appKitRect: CGRect(
                x: x.doubleValue,
                y: y.doubleValue,
                width: width.doubleValue,
                height: height.doubleValue
            ),
            source: source,
            processIdentifier: responseProcessIdentifier
        )
    }
}

final class CaretLocator {
    static let shared = CaretLocator()

    private let query: PaletteCaretQuerying
    private let targetProvider: () -> CaretTarget?
    private let screensProvider: () -> [PaletteScreenGeometry]
    private let diagnosticState = CaretDiagnosticState()

    init(
        query: PaletteCaretQuerying = PaletteCaretClient(),
        targetProvider: @escaping () -> CaretTarget? = {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  let bundleIdentifier = application.bundleIdentifier else {
                return nil
            }
            return CaretTarget(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundleIdentifier
            )
        },
        screensProvider: @escaping () -> [PaletteScreenGeometry] = {
            NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else {
                    return nil
                }
                return PaletteScreenGeometry(
                    appKitFrame: screen.frame,
                    cgDisplayBounds: CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
                )
            }
        }
    ) {
        self.query = query
        self.targetProvider = targetProvider
        self.screensProvider = screensProvider
    }

    func currentCaretLocation() -> CaretLocation? {
        guard let target = targetProvider() else {
            diagnosticState.record(status: "no-frontmost-target", processIdentifier: nil, location: nil)
            return nil
        }
        guard let response = query.query(target: target) else {
            diagnosticState.record(
                status: "palette-unavailable",
                processIdentifier: target.processIdentifier,
                location: nil
            )
            return nil
        }
        guard response.processIdentifier == target.processIdentifier else {
            diagnosticState.record(
                status: "palette-response-mismatch",
                processIdentifier: target.processIdentifier,
                location: nil
            )
            return nil
        }
        guard let globalRect = PaletteCaretGeometry.cgCaretRect(
            fromAppKit: response.appKitRect,
            screens: screensProvider()
        ) else {
            diagnosticState.record(
                status: "invalid-palette-geometry",
                processIdentifier: target.processIdentifier,
                location: nil
            )
            return nil
        }

        let location = CaretLocation(
            globalRect: globalRect,
            anchorPoint: CGPoint(x: globalRect.maxX, y: globalRect.maxY),
            processIdentifier: target.processIdentifier,
            applicationBundleIdentifier: target.bundleIdentifier,
            source: response.source,
            confidence: response.source == .paletteLineRectangle ? 1 : 0.95,
            isStale: false
        )
        diagnosticState.record(
            status: "located",
            processIdentifier: target.processIdentifier,
            location: location
        )
        return location
    }

    func diagnosticReport() -> CaretDiagnosticReport {
        diagnosticState.report()
    }
}
