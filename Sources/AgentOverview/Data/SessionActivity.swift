import Foundation

/// What a working session is doing right now, derived from the tail of its transcript
/// (the last tool call). `thinking` is the default when nothing more specific is known.
enum SessionActivity: String, CaseIterable, Equatable, Sendable {
    /// Streaming text, no tool call in flight.
    case thinking
    /// Editing or writing files (Edit, Write, MultiEdit, NotebookEdit).
    case coding
    /// Running commands (Bash and the like).
    case running
    /// Reading or searching (Read, Grep, Glob, WebSearch, WebFetch).
    case reading
    /// Subagents are running on its behalf (Agent tool, Workflow).
    case delegating

    /// Short label for the status line.
    var label: String {
        switch self {
        case .thinking: "Thinking"
        case .coding: "Coding"
        case .running: "Running commands"
        case .reading: "Reading"
        case .delegating: "Delegating"
        }
    }
}
