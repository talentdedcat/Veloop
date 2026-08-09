import AppKit
import Carbon
import Foundation

@MainActor
final class PaletteInputSourceInstaller {
    private static let bundleIdentifier = "com.talentdedcat.veloop.palette"
    private static let comparedBundlePaths = [
        "Contents/MacOS/VeloopPalette",
        "Contents/Info.plist",
    ]
    private static let inputSourceDisableGracePeriod: TimeInterval = 0.1
    private static let helperTerminationTimeout: TimeInterval = 0.2
    private static let helperTerminationPollInterval: TimeInterval = 0.01

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureInstalled() throws {
        let embeddedURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Input Methods/VeloopPalette.app")
        guard fileManager.fileExists(atPath: embeddedURL.path) else {
            throw PaletteInputSourceInstallerError.missingEmbeddedHelper
        }

        let inputMethodsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
        let installedURL = inputMethodsURL
            .appendingPathComponent("VeloopPalette.app", isDirectory: true)
        try fileManager.createDirectory(
            at: inputMethodsURL,
            withIntermediateDirectories: true
        )
        try writeHostMarker()

        if helperNeedsReplacement(embeddedURL: embeddedURL, installedURL: installedURL) {
            disableInstalledSource()
            Thread.sleep(forTimeInterval: Self.inputSourceDisableGracePeriod)
            stopInstalledHelper()
            if fileManager.fileExists(atPath: installedURL.path) {
                try fileManager.removeItem(at: installedURL)
            }
            try fileManager.copyItem(at: embeddedURL, to: installedURL)
        }

        let registrationStatus = TISRegisterInputSource(installedURL as CFURL)
        guard registrationStatus == noErr else {
            throw PaletteInputSourceInstallerError.registrationFailed(registrationStatus)
        }
    }

    private func writeHostMarker() throws {
        let supportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Veloop", isDirectory: true)
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let markerURL = supportURL.appendingPathComponent("palette-host-path")
        try Data(Bundle.main.bundleURL.standardizedFileURL.path.utf8)
            .write(to: markerURL, options: .atomic)
    }

    private func helperNeedsReplacement(embeddedURL: URL, installedURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: installedURL.path) else { return true }
        for relativePath in Self.comparedBundlePaths {
            let embeddedItem = embeddedURL.appendingPathComponent(relativePath)
            let installedItem = installedURL.appendingPathComponent(relativePath)
            guard let embeddedData = try? Data(contentsOf: embeddedItem, options: .mappedIfSafe),
                  let installedData = try? Data(contentsOf: installedItem, options: .mappedIfSafe),
                  embeddedData == installedData else {
                return true
            }
        }
        return false
    }

    private func stopInstalledHelper() {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ) {
            application.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + Self.helperTerminationTimeout
            while !application.isTerminated,
                  ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: Self.helperTerminationPollInterval)
            }
            if !application.isTerminated {
                Darwin.kill(application.processIdentifier, SIGTERM)
            }
        }
    }

    private func disableInstalledSource() {
        guard let source = matchingInputSource() else { return }
        _ = TISDeselectInputSource(source)
        _ = TISDisableInputSource(source)
    }

    private func matchingInputSource() -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceID as String: Self.bundleIdentifier,
        ] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(filter, true) else {
            return nil
        }
        let sources = unmanagedSources.takeRetainedValue() as NSArray
        guard let first = sources.firstObject else { return nil }
        return ((first as AnyObject) as! TISInputSource)
    }
}

private enum PaletteInputSourceInstallerError: Error {
    case missingEmbeddedHelper
    case registrationFailed(OSStatus)
}
