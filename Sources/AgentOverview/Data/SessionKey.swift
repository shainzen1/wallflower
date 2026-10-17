import Foundation

/// The identity of a session across scans, whatever wrote it. A Claude Code session is its process
/// (`pid`; its session id rotates across resumes, the process does not). A session from another tool
/// (`docs/external-sessions.md`) is the `id` of its file. The two cases never collide, so every
/// per-session state of the panel (acknowledgements, hidden sessions, hop and excited tokens, the
/// held face of a throw) keys on this.
enum SessionKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// A Claude Code session, by its process.
    case claude(pid_t)
    /// A session from another tool, by the `id` in its file.
    case external(String)

    var isClaude: Bool {
        if case .claude = self { return true }
        return false
    }

    /// The Claude Code process, nil for an external session (its optional pid lives on the session).
    var claudePid: pid_t? {
        if case .claude(let pid) = self { return pid }
        return nil
    }

    /// A short stable string: the pid for a Claude session (as the stack ids always were), `x:<id>`
    /// for an external one.
    var description: String {
        switch self {
        case .claude(let pid): "\(pid)"
        case .external(let id): "x:\(id)"
        }
    }

    /// Claude sessions first (by pid), then external ones (by id). Only a tiebreaker of the sort.
    static func < (lhs: SessionKey, rhs: SessionKey) -> Bool {
        switch (lhs, rhs) {
        case (.claude(let a), .claude(let b)): a < b
        case (.claude, .external): true
        case (.external, .claude): false
        case (.external(let a), .external(let b)): a < b
        }
    }
}

/// Where a session comes from: Claude Code's own registry, or a file another tool wrote into the
/// external sessions folder (`docs/external-sessions.md`).
enum SessionSourceKind: Hashable, Sendable {
    case claude
    /// `tool` is the file's short display name ("codex"); empty when the file gave none.
    case external(tool: String)

    var isClaude: Bool { self == .claude }

    /// The tool name the bulge shows before the status, nil for Claude sessions and nameless tools.
    var toolName: String? {
        guard case .external(let tool) = self, !tool.isEmpty else { return nil }
        return tool
    }
}
