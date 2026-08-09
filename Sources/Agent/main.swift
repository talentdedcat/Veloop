import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.prohibited)
withExtendedLifetime(delegate) {
    application.run()
}
