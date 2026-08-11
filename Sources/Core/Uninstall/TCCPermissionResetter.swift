import Foundation

public protocol TCCPermissionResetting: Sendable {
    func resetVeloopPermissions() throws
}

public struct TCCPermissionResetter: TCCPermissionResetting, Sendable {
    public typealias Runner = @Sendable (URL, [String]) throws -> Int32

    private static let requiredCommands = [
        ["reset", "ListenEvent", "com.veloop.app"],
        ["reset", "Accessibility", "com.veloop.app"],
        ["reset", "PostEvent", "com.veloop.app"],
    ]

    private static let legacyCommands = [
        ["reset", "ListenEvent", "com.veloop.service"],
        ["reset", "Accessibility", "com.veloop.service"],
        ["reset", "PostEvent", "com.veloop.service"],
    ]

    private let runner: Runner

    public init() {
        runner = { executable, arguments in
            try Self.run(executable, arguments)
        }
    }

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    public func resetVeloopPermissions() throws {
        let executable = URL(fileURLWithPath: "/usr/bin/tccutil")
        for arguments in Self.requiredCommands {
            let status = try runner(executable, arguments)
            guard status == 0 else {
                throw TCCPermissionResetError.commandFailed(arguments, status)
            }
        }
        for arguments in Self.legacyCommands {
            let status = try runner(executable, arguments)
            guard status == 0 || status == 64 else {
                throw TCCPermissionResetError.commandFailed(arguments, status)
            }
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

private enum TCCPermissionResetError: Error {
    case commandFailed([String], Int32)
}
