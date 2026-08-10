import AppKit
import Foundation

public enum VeloopCLI {
    public static func run(arguments: [String]) -> Int32 {
        do {
            let paths = try StoragePaths.userDefault()
            let controller = CommandLineController(
                requester: AgentClient(socketURL: paths.socket),
                openDataDirectory: {
                    try? paths.createDirectories()
                    return NSWorkspace.shared.open(paths.root)
                },
                uninstallPurge: {
                    try VeloopCleanupController.live().cleanup(
                        scope: .purgeUserData,
                        includeWatcher: true
                    )
                }
            )
            let result = controller.run(arguments: arguments)
            if !result.standardOutput.isEmpty {
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
            }
            if !result.standardError.isEmpty {
                FileHandle.standardError.write(Data(result.standardError.utf8))
            }
            return result.exitCode
        } catch {
            FileHandle.standardError.write(Data("Could not locate the Veloop data directory.\n".utf8))
            return 1
        }
    }
}
