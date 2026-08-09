import Carbon
import Foundation

public struct PaletteInputSourceStatus: Equatable, Sendable {
    public let installed: Bool
    public let enabled: Bool
    public let selected: Bool

    public init(installed: Bool, enabled: Bool, selected: Bool) {
        self.installed = installed
        self.enabled = enabled
        self.selected = selected
    }
}

public enum PaletteInputSourceActivator {
    public static let inputSourceIdentifier = "com.talentdedcat.veloop.palette"
    static let startupRetryDelaysNanoseconds: [UInt64] = [
        0,
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        4_000_000_000,
    ]

    @discardableResult
    public static func activate() -> Bool {
        precondition(Thread.isMainThread)
        guard let source = matchingInputSource() else { return false }
        guard TISEnableInputSource(source) == noErr else { return false }
        return TISSelectInputSource(source) == noErr
    }

    @discardableResult
    public static func deactivate() -> Bool {
        precondition(Thread.isMainThread)
        guard let source = matchingInputSource() else { return true }
        return TISDeselectInputSource(source) == noErr
    }

    public static func status() -> PaletteInputSourceStatus {
        status(for: matchingInputSource())
    }

    static func status(for source: TISInputSource?) -> PaletteInputSourceStatus {
        guard let source else {
            return PaletteInputSourceStatus(installed: false, enabled: false, selected: false)
        }
        return PaletteInputSourceStatus(
            installed: true,
            enabled: booleanProperty(kTISPropertyInputSourceIsEnabled, source: source),
            selected: booleanProperty(kTISPropertyInputSourceIsSelected, source: source)
        )
    }

    @MainActor
    public static func activateDuringStartup() -> Task<Void, Never> {
        Task { @MainActor in
            for delay in startupRetryDelaysNanoseconds {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                if activate() { return }
            }
        }
    }

    private static func matchingInputSource() -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceID as String: inputSourceIdentifier,
        ] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(filter, true) else {
            return nil
        }
        let sources = unmanagedSources.takeRetainedValue() as NSArray
        guard let first = sources.firstObject else { return nil }
        return ((first as AnyObject) as! TISInputSource)
    }

    private static func booleanProperty(_ property: CFString, source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
