import Foundation
import WallflowerHookCore

/// One session as a scan saw it, whatever its source: what `Session` is built from and updated with.
/// The Claude registry's `SessionRecord` and an external `ExternalSessionRecord` both map to it, so the
/// store, the sort and the rows treat both alike.
struct SessionSnapshot: Sendable, Equatable {
    var key: SessionKey
    /// The process whose exit ends the session: always set for Claude, optional for external ones.
    var pid: pid_t?
    var source: SessionSourceKind
    var startedAt: Date
    var name: String
    var cwd: String
    /// `local_<uuid>` for Claude desktop sessions: the deep link.
    var hostSessionId: String?
    /// The Claude registry's `entrypoint`; empty for external sessions.
    var entrypoint: String
    var state: SessionState
    var stateSince: Date
    /// How a click brings an external session forward; nil for Claude sessions.
    var opener: ExternalOpener?
    /// The Claude conversation id, for the transcript insights; nil for external sessions.
    var transcriptSessionId: String?

    init(record: SessionRecord) {
        key = .claude(record.pid)
        pid = record.pid
        source = .claude
        startedAt = record.startedDate
        name = Self.displayName(name: record.name, cwd: record.cwd, fallback: "Session \(record.pid)")
        cwd = record.cwd
        hostSessionId = record.hostSessionId
        entrypoint = record.entrypoint
        state = SessionState(record: record)
        stateSince = record.statusUpdatedDate
        opener = nil
        transcriptSessionId = record.sessionId
    }

    init(external record: ExternalSessionRecord) {
        key = .external(record.id)
        pid = record.pid
        source = .external(tool: record.tool ?? "")
        startedAt = record.startedDate
        let cwd = record.cwd ?? ""
        name = Self.displayName(name: record.name, cwd: cwd, fallback: record.tool.map { "\(AgentTool.displayName(forTool: $0)) session" } ?? record.id)
        self.cwd = cwd
        hostSessionId = nil
        entrypoint = ""
        state = SessionState(status: record.status, waitingKind: record.waitingKind)
        stateSince = record.statusUpdatedDate
        opener = record.open
        transcriptSessionId = nil
    }

    /// The given name, else the last path component of `cwd`, else `fallback`.
    static func displayName(name: String?, cwd: String, fallback: String) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let folder = cwd.split(separator: "/").last(where: { !$0.isEmpty && $0 != "." }) {
            return String(folder)
        }
        return fallback
    }
}
