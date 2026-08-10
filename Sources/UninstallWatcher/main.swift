import Foundation
import VeloopCore

do {
    let watcher = try InstalledAppWatcher.live()
    try watcher.start()
    RunLoop.main.run()
} catch {
    Darwin.exit(1)
}
