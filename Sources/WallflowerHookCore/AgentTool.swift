import Foundation

/// The agents whose hooks call `wallflower-hook` (`docs/agents.md`). The raw value is the canonical
/// id: the helper's first argument, the `tool` in the session files it writes, and the prefix of their
/// ids (`codex-<session id>`). OpenCode is here too although its plugin writes the files itself.
public enum AgentTool: String, CaseIterable, Sendable {
    case codex
    case copilot
    case gemini
    case cursor
    case opencode
    case windsurf
    case goose
    case devin

    /// The name the hover (after the session name) and Settings show ("Codex").
    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .copilot: "Copilot"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .windsurf: "Windsurf"
        case .goose: "Goose"
        case .devin: "Devin"
        }
    }

    /// The display name for a session file's `tool`: a known id maps to its name, anything else
    /// (a hand-written tool) stays as written.
    public static func displayName(forTool tool: String) -> String {
        AgentTool(rawValue: tool.lowercased())?.displayName ?? tool
    }
}

/// What a session file says about its session, as the helper writes it (`docs/external-sessions.md`).
public enum HookStatus: String, Sendable {
    case busy, idle, waiting
}

/// `waitingFor` while `waiting`.
public enum HookWaitingFor: String, Sendable {
    case question, permission
}

/// What one hook event does to its session's file.
public enum HookAction: Equatable, Sendable {
    /// The session exists: create its file as idle, or leave a known status alone (a resume or a
    /// compaction mid-turn must not reset a working session).
    case start
    /// The session is in this state now.
    case status(HookStatus, waitingFor: HookWaitingFor? = nil)
    /// The session ended: delete its file.
    case end
    /// Nothing to do (an event the tool sends that says nothing about the status).
    case ignore
}
