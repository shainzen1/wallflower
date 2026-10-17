import Foundation
import Observation

/// One live session as the UI sees it: a Claude Code session, or one another tool wrote into the
/// external sessions folder. Identity is the `key` (`SessionKey`): the `pid` for Claude sessions
/// (session ids rotate across resumes, the process does not), the file's `id` for external ones.
/// Updated in place by the store so only the rows that change re-render.
@Observable @MainActor
final class Session: Identifiable {
    nonisolated let key: SessionKey
    nonisolated var id: SessionKey { key }
    /// The process whose exit ends the session: always set for Claude, optional for external sessions.
    nonisolated let pid: pid_t?
    /// Claude, or the external tool's name.
    nonisolated let source: SessionSourceKind
    let startedAt: Date

    private(set) var name: String
    private(set) var cwd: String
    private(set) var hostSessionId: String?
    private(set) var entrypoint: String
    /// How a click brings an external session forward (nil for Claude sessions, and when the file gave none).
    private(set) var opener: ExternalOpener?
    private(set) var state: SessionState
    /// When the current state began (`statusUpdatedAt` in the registry).
    private(set) var stateSince: Date
    /// Set when a busy to idle transition was observed; cleared after `DataTuning.justFinishedDuration`.
    private(set) var justFinishedUntil: Date?
    /// The process exited or its registry file disappeared. The store removes the session shortly after.
    private(set) var ended = false
    /// What the session is doing while working (from the transcript tail). Defaults to thinking.
    private(set) var activity: SessionActivity = .thinking
    /// Subagents currently running for this session (from the transcript's subagents folder).
    private(set) var subagentCount = 0
    /// Git branch of the working directory, when known.
    private(set) var gitBranch: String?
    /// The last tool call ended in an error.
    private(set) var lastToolFailed = false
    /// How long a fresh idle period counts as your turn (`Theme.yourTurnFor`; tests shorten it).
    @ObservationIgnored let yourTurnFor: TimeInterval
    /// Bumped once when the your-turn window of the current idle period closes, so the rows that
    /// read `idleTier` re-derive without any polling.
    private(set) var yourTurnExpiries = 0

    convenience init(record: SessionRecord, yourTurnFor: TimeInterval = Theme.yourTurnFor, now: Date = Date()) {
        self.init(snapshot: SessionSnapshot(record: record), yourTurnFor: yourTurnFor, now: now)
    }

    init(snapshot: SessionSnapshot, yourTurnFor: TimeInterval = Theme.yourTurnFor, now: Date = Date()) {
        self.yourTurnFor = yourTurnFor
        key = snapshot.key
        pid = snapshot.pid
        source = snapshot.source
        startedAt = snapshot.startedAt
        name = snapshot.name
        cwd = snapshot.cwd
        hostSessionId = snapshot.hostSessionId
        entrypoint = snapshot.entrypoint
        opener = snapshot.opener
        state = snapshot.state
        stateSince = snapshot.stateSince
        // A session already idle at launch keeps its tier: the registry's status time is the idle start.
        armYourTurnExpiry(now: now)
    }

    func apply(record: SessionRecord, now: Date = Date()) {
        apply(snapshot: SessionSnapshot(record: record), now: now)
    }

    /// Updates the fields that changed and detects the busy to idle transition.
    func apply(snapshot: SessionSnapshot, now: Date = Date()) {
        if name != snapshot.name { name = snapshot.name }
        if cwd != snapshot.cwd { cwd = snapshot.cwd }
        if hostSessionId != snapshot.hostSessionId { hostSessionId = snapshot.hostSessionId }
        if entrypoint != snapshot.entrypoint { entrypoint = snapshot.entrypoint }
        if opener != snapshot.opener { opener = snapshot.opener }

        let newState = snapshot.state
        let newSince = snapshot.stateSince
        let sinceChanged = stateSince != newSince
        if sinceChanged { stateSince = newSince }
        guard state != newState else {
            if sinceChanged { armYourTurnExpiry(now: now) }
            return
        }

        let finished = state == .working && newState == .idle
        state = newState
        if finished {
            beginJustFinished(at: now)
        } else if justFinishedUntil != nil {
            justFinishedUntil = nil
        }
        armYourTurnExpiry(now: now)
    }

    /// Applies transcript-derived facts; only changed fields are written so observers stay quiet.
    func apply(insight: SessionInsight) {
        if activity != insight.activity { activity = insight.activity }
        if subagentCount != insight.subagentCount { subagentCount = insight.subagentCount }
        if gitBranch != insight.gitBranch { gitBranch = insight.gitBranch }
        if lastToolFailed != insight.lastToolFailed { lastToolFailed = insight.lastToolFailed }
    }

    func markEnded() {
        if !ended { ended = true }
    }

    func isJustFinished(at now: Date = Date()) -> Bool {
        guard let until = justFinishedUntil else { return false }
        return now < until
    }

    /// The tier of the current idle period (`IdleTier.tier`; meaningless while not idle). Reading it
    /// subscribes to the expiry bump, so a row in your turn becomes idle when the window closes.
    func idleTier(acknowledgedAt: Date?, now: Date = Date()) -> IdleTier {
        _ = yourTurnExpiries
        return IdleTier.tier(idleSince: stateSince, acknowledgedAt: acknowledgedAt, now: now, yourTurnFor: yourTurnFor)
    }

    /// Group order in the panel (`SessionState.sortRank(idleTier:)`).
    func sortRank(acknowledgedAt: Date?, now: Date = Date()) -> Int {
        state.sortRank(idleTier: idleTier(acknowledgedAt: acknowledgedAt, now: now))
    }

    /// Registry name, else the last path component of `cwd`, else "Session <pid>".
    nonisolated static func displayName(for record: SessionRecord) -> String {
        SessionSnapshot(record: record).name
    }

    // MARK: Private

    /// One-shot at the end of the current idle period's your-turn window: bumps `yourTurnExpiries`
    /// so observers re-derive the tier, unless the session left that idle period meanwhile (a
    /// newer arming then owns the next expiry). Nothing is armed when the window is already over.
    private func armYourTurnExpiry(now: Date) {
        guard state == .idle else { return }
        let since = stateSince
        let remaining = since.addingTimeInterval(yourTurnFor).timeIntervalSince(now)
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .idle, self.stateSince == since else { return }
                self.yourTurnExpiries += 1
            }
        }
    }

    private func beginJustFinished(at now: Date) {
        let until = now.addingTimeInterval(DataTuning.justFinishedDuration)
        justFinishedUntil = until
        // One-shot: clears the flag so observers see the change, unless a newer transition replaced it.
        DispatchQueue.main.asyncAfter(deadline: .now() + DataTuning.justFinishedDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.justFinishedUntil == until else { return }
                self.justFinishedUntil = nil
            }
        }
    }
}
