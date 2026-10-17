/// What a `waiting` session is waiting for, derived from the raw `waitingFor` string.
enum WaitingKind: Sendable, Hashable {
    /// `"input needed"`: AskUserQuestion, an MCP elicitation, teammate setup.
    case question
    /// `"permission prompt"`: the normal tool permission dialog.
    case permission
    /// Anything else (`"dialog open"`, `"sandbox request"`, absent, unknown).
    case other

    /// Short label for the playground.
    var label: String {
        switch self {
        case .question: "question"
        case .permission: "permission"
        case .other: "other"
        }
    }

    init(waitingFor: String?) {
        switch waitingFor {
        case "input needed": self = .question
        case "permission prompt": self = .permission
        default: self = .other
        }
    }
}
