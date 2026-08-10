import AppKit
import Darwin
import VeloopCore

MainActor.assumeIsolated {
    let mode = AppLaunchMode(arguments: Array(CommandLine.arguments.dropFirst()))
    guard mode != .invalid else {
        Darwin.exit(2)
    }

    let application = NSApplication.shared
    let delegate: NSObject & NSApplicationDelegate
    switch mode {
    case .control:
        application.setActivationPolicy(.regular)
        delegate = AppDelegate()
    case .agent:
        application.setActivationPolicy(.prohibited)
        delegate = AgentAppDelegate()
    case .invalid:
        fatalError("launch mode was validated before application startup")
    }
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
}
