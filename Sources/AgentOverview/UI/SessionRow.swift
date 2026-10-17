import Foundation

/// One row of the panel, as a value derived from a `Session`. The face status, the label
/// and the identity seed are decided here so the views stay free of status logic.
struct SessionRow: Identifiable, Equatable, Sendable {
    /// The session's identity (`SessionKey`): every per-row state of the panel keys on it.
    let key: SessionKey
    /// The session's process: always set for Claude, optional for external sessions.
    let pid: pid_t?
    /// Claude, or the external tool (its name leads the status line).
    let source: SessionSourceKind
    /// How a click brings an external session forward; nil for Claude sessions.
    let opener: ExternalOpener?
    /// The session's working directory (an external session's open command runs there).
    let cwd: String
    let name: String
    /// What the face shows.
    let status: FaceStatus
    /// The status as words: `Needs input`, `Needs permission`, `Working · Coding`, `Your turn`, `Idle`,
    /// `Finished`, `Ended`. An external session's has no activity (its transcript is unknown): `Working`.
    let label: String
    /// When the current state began (the registry's `statusUpdatedAt`).
    let stateSince: Date
    /// `local_<uuid>` for desktop sessions; the click opens this chat.
    let hostSessionId: String?
    /// What started the session (`claude-desktop`, `cli`, `claude-vscode`): a click on a session that is
    /// not the desktop app's brings its terminal or editor forward (`SessionOpener`).
    let entrypoint: String
    /// The process exited; the row is on its way out.
    let ended: Bool
    /// What the session is doing while working (the face's working substate).
    let activity: SessionActivity
    /// Subagents running for the session (satellites around a working face).
    let subagentCount: Int
    /// Git branch of the working directory, when known (third line of the bulge).
    let gitBranch: String?
    /// A stable short key of the project (the last path component of `cwd`): the dot colour.
    let projectKey: String

    var id: SessionKey { key }

    /// The external tool's name, which leads the status line (`codex · Working · 2m`); nil for Claude.
    var tool: String? { source.toolName }

    /// Seed of the face identity: the desktop session id when there is one, else the pid; an external
    /// session's file id.
    var seed: String { Self.seed(key: key, hostSessionId: hostSessionId) }

    static func seed(key: SessionKey, hostSessionId: String?) -> String {
        if let hostSessionId { return hostSessionId }
        switch key {
        case .claude(let pid): return "pid-\(pid)"
        case .external(let id): return "external-\(id)"
        }
    }

    /// - Parameter acknowledgedAt: when the person last opened this session's chat (`PanelModel`).
    @MainActor
    init(session: Session, now: Date = Date(), acknowledgedAt: Date? = nil) {
        key = session.key
        pid = session.pid
        source = session.source
        opener = session.opener
        cwd = session.cwd
        name = session.name
        stateSince = session.stateSince
        hostSessionId = session.hostSessionId
        entrypoint = session.entrypoint
        ended = session.ended
        activity = session.activity
        subagentCount = session.subagentCount
        gitBranch = session.gitBranch
        let folderKey = Self.projectKey(cwd: session.cwd)
        // An external session without a folder still gets a stable colour: its tool's, else its own.
        projectKey = folderKey.isEmpty ? (session.source.toolName ?? session.key.description) : folderKey
        status = Self.faceStatus(
            state: session.state,
            isJustFinished: session.isJustFinished(at: now),
            ended: session.ended,
            stateSince: session.stateSince,
            idleTier: session.idleTier(acknowledgedAt: acknowledgedAt, now: now)
        )
        label = Self.label(for: status, activity: activity, source: source)
    }

    /// Direct construction of a Claude row for tests and the playground.
    init(
        pid: pid_t,
        name: String,
        status: FaceStatus,
        stateSince: Date,
        hostSessionId: String?,
        ended: Bool,
        activity: SessionActivity = .thinking,
        subagentCount: Int = 0,
        gitBranch: String? = nil,
        projectKey: String = "",
        entrypoint: String = "claude-desktop"
    ) {
        self.init(
            key: .claude(pid), pid: pid, source: .claude, name: name, status: status, stateSince: stateSince,
            hostSessionId: hostSessionId, ended: ended, activity: activity, subagentCount: subagentCount,
            gitBranch: gitBranch, projectKey: projectKey, entrypoint: entrypoint
        )
    }

    /// Direct construction of any row.
    init(
        key: SessionKey,
        pid: pid_t?,
        source: SessionSourceKind,
        opener: ExternalOpener? = nil,
        cwd: String = "",
        name: String,
        status: FaceStatus,
        stateSince: Date,
        hostSessionId: String?,
        ended: Bool,
        activity: SessionActivity = .thinking,
        subagentCount: Int = 0,
        gitBranch: String? = nil,
        projectKey: String = "",
        entrypoint: String = "claude-desktop"
    ) {
        self.key = key
        self.pid = pid
        self.source = source
        self.opener = opener
        self.cwd = cwd
        self.name = name
        self.status = status
        self.label = Self.label(for: status, activity: activity, source: source)
        self.stateSince = stateSince
        self.hostSessionId = hostSessionId
        self.entrypoint = entrypoint
        self.ended = ended
        self.activity = activity
        self.subagentCount = subagentCount
        self.gitBranch = gitBranch
        self.projectKey = projectKey
    }

    /// The same row forced into a `--demo-states` look: working with the given activity and satellites, a branch.
    func demo(activity: SessionActivity = RowDemo.activity, subagentCount: Int = RowDemo.subagentCount, projectKey: String = RowDemo.projectKey) -> SessionRow {
        SessionRow(
            key: key, pid: pid, source: source, opener: opener, cwd: cwd, name: name, status: .working, stateSince: stateSince, hostSessionId: hostSessionId, ended: ended,
            activity: activity, subagentCount: subagentCount, gitBranch: gitBranch ?? RowDemo.gitBranch, projectKey: projectKey,
            entrypoint: entrypoint
        )
    }

    /// Session state to face status. Ended wins over everything; a busy to idle transition
    /// shows the happy flash while the session counts as just finished, then an idle session is
    /// your turn or idle by its tier (`IdleTier.tier`: fresh and not acknowledged is your turn).
    static func faceStatus(state: SessionState, isJustFinished: Bool, ended: Bool, stateSince: Date, idleTier: IdleTier = .idle) -> FaceStatus {
        if ended { return .ended }
        switch state {
        case .needsInput(let kind): return .needsInput(kind: kind)
        case .working: return .working
        case .idle:
            if isJustFinished { return .justFinished }
            return idleTier == .yourTurn ? .yourTurn(since: stateSince) : .idle(since: stateSince)
        }
    }

    /// The status as words, without an activity. A waiting session says what it waits for:
    /// `Needs input` (a question), `Needs permission` (a tool permission), `Needs you` (anything else).
    static func label(for status: FaceStatus) -> String {
        switch status {
        case .needsInput(.question): "Needs input"
        case .needsInput(.permission): "Needs permission"
        case .needsInput(.other): "Needs you"
        case .working: "Working"
        case .yourTurn: "Your turn"
        case .idle: "Idle"
        case .justFinished: "Finished"
        case .ended: "Ended"
        }
    }

    /// The status as words; while working the activity follows: `Working · Coding`. An external
    /// session shows no activity (its transcript is unknown): `Working`.
    static func label(for status: FaceStatus, activity: SessionActivity, source: SessionSourceKind = .claude) -> String {
        let base = label(for: status)
        guard source.isClaude, status == .working else { return base }
        return "\(base) · \(activity.label)"
    }

    /// The project key of a working directory: its last path component, or the whole string
    /// when there is none (so every session has a stable dot colour).
    static func projectKey(cwd: String) -> String {
        if let folder = cwd.split(separator: "/").last(where: { !$0.isEmpty && $0 != "." }) {
            return String(folder)
        }
        return cwd
    }
}
