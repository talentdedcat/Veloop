public enum AppLaunchMode: Equatable, Sendable {
    case control
    case agent
    case invalid

    public init(arguments: [String]) {
        switch arguments {
        case []:
            self = .control
        case ["--agent"]:
            self = .agent
        default:
            self = .invalid
        }
    }
}
