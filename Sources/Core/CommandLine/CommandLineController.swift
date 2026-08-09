import Foundation

struct CommandLineResult: Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

final class CommandLineController {
    private let requester: AgentRequesting
    private let openDataDirectory: () -> Bool

    init(requester: AgentRequesting, openDataDirectory: @escaping () -> Bool) {
        self.requester = requester
        self.openDataDirectory = openDataDirectory
    }

    func run(arguments: [String]) -> CommandLineResult {
        guard let command = arguments.first else {
            return usage()
        }
        if command == "version" {
            return success(AppConstants.version)
        }
        if command == "open-data-directory" {
            return openDataDirectory()
                ? success("")
                : failure("Could not open the Veloop data directory.")
        }

        let request: AgentRequest
        switch command {
        case "status", "pause", "resume", "clear", "count", "storage", "doctor", "restart":
            guard arguments.count == 1 else {
                return usage()
            }
            request = AgentRequest(command: command, arguments: [])
        case "config" where arguments == ["config", "get"]:
            request = AgentRequest(command: "config-get", arguments: [])
        case "config" where arguments.count == 4 && arguments[1] == "set":
            request = AgentRequest(command: "config-set", arguments: Array(arguments[2...3]))
        default:
            return usage()
        }

        do {
            let response = try requester.send(request)
            if response.succeeded {
                return success(response.output ?? "")
            }
            return failure(response.error ?? "The command failed.")
        } catch AgentClientError.agentUnavailable {
            return failure("Veloop is not running. Open Veloop from /Applications or run veloopctl restart.")
        } catch {
            return failure("Could not communicate with Veloop.")
        }
    }

    private func success(_ output: String) -> CommandLineResult {
        CommandLineResult(
            exitCode: 0,
            standardOutput: output.isEmpty ? "" : output + "\n",
            standardError: ""
        )
    }

    private func failure(_ error: String) -> CommandLineResult {
        CommandLineResult(exitCode: 1, standardOutput: "", standardError: error + "\n")
    }

    private func usage() -> CommandLineResult {
        CommandLineResult(
            exitCode: 2,
            standardOutput: "",
            standardError: "Usage: veloopctl status|pause|resume|clear|count|storage|doctor|config get|config set <key> <value>|open-data-directory|restart|version\n"
        )
    }
}
