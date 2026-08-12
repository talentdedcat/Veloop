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
    private static let helperSignalTerminationTimeout: TimeInterval = 0.5
    private static let helperForcedTerminationTimeout: TimeInterval = 0.5
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
            try stopInstalledHelper(installedURL: installedURL)
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

    private func stopInstalledHelper(installedURL: URL) throws {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        )
        for application in applications {
            application.terminate()
        }

        var processIdentifiers = Set(applications.map(\.processIdentifier))
        processIdentifiers.formUnion(installedHelperProcessIdentifiers(installedURL: installedURL))
        for processIdentifier in processIdentifiers {
            guard !waitForTermination(
                processIdentifier: processIdentifier,
                timeout: Self.helperTerminationTimeout
            ) else { continue }

            Darwin.kill(processIdentifier, SIGTERM)
            guard !waitForTermination(
                processIdentifier: processIdentifier,
                timeout: Self.helperSignalTerminationTimeout
            ) else { continue }

            Darwin.kill(processIdentifier, SIGKILL)
            guard waitForTermination(
                processIdentifier: processIdentifier,
                timeout: Self.helperForcedTerminationTimeout
            ) else {
                throw PaletteInputSourceInstallerError.helperTerminationFailed
            }
        }
    }

    private func installedHelperProcessIdentifiers(installedURL: URL) -> Set<pid_t> {
        let expectedPath = installedURL
            .appendingPathComponent("Contents/MacOS/VeloopPalette")
            .standardizedFileURL.path
        var processIdentifiers = [pid_t](repeating: 0, count: 4_096)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &processIdentifiers,
            Int32(processIdentifiers.count * MemoryLayout<pid_t>.size)
        )
        guard byteCount > 0 else { return [] }

        let count = min(Int(byteCount) / MemoryLayout<pid_t>.size, processIdentifiers.count)
        return Set(processIdentifiers.prefix(count).filter { processIdentifier in
            guard processIdentifier > 0 else { return false }
            var pathBuffer = [CChar](repeating: 0, count: 4_096)
            guard proc_pidpath(
                processIdentifier,
                &pathBuffer,
                UInt32(pathBuffer.count)
            ) > 0 else { return false }
            return URL(fileURLWithPath: String(cString: pathBuffer))
                .standardizedFileURL.path == expectedPath
        })
    }

    private func waitForTermination(
        processIdentifier: pid_t,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while isProcessRunning(processIdentifier),
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: Self.helperTerminationPollInterval)
        }
        return !isProcessRunning(processIdentifier)
    }

    private func isProcessRunning(_ processIdentifier: pid_t) -> Bool {
        Darwin.kill(processIdentifier, 0) == 0 || errno != ESRCH
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
    case helperTerminationFailed
    case registrationFailed(OSStatus)
}
