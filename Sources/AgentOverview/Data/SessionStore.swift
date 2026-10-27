import Foundation
import Observation

/// The list of live sessions the UI renders. Fed off the main actor by a `RegistryWatcher` on the
/// Claude Code registry and, when `externalFolder` is set, one on the external sessions folder
/// (`docs/external-sessions.md`); every mutation of `sessions` and of the `Session` objects happens
/// here, on the main actor. Both sources become `SessionSnapshot`s, so the rest treats them alike;
/// each source's scan only ever ends sessions of its own kind.
///
/// Order: needs input first, then working, then your turn, then idle (`SessionState.sortRank(idleTier:)`);
/// inside a group the most recent state change first, the key as the tiebreaker. The store knows no
/// acknowledgements; `PanelModel` re-sorts with them. Ended sessions keep their place for
/// `DataTuning.endedLinger` so the UI can fade them out, then they are removed.
@Observable @MainActor
final class SessionStore {
    private(set) var sessions: [Session] = []
    /// True once the initial scan of every watched source has been applied.
    private(set) var hasScanned = false
    /// Pids of every live registry file in the last scan, whatever its entrypoint: the sessions this
    /// store filters out are among them.
    @ObservationIgnored private(set) var presentPids: Set<pid_t> = []
    /// Ids of every live external session file in the last external scan.
    @ObservationIgnored private(set) var presentExternalIDs: Set<String> = []
    /// Called once, after the initial scan, with the number of sessions found.
    @ObservationIgnored var onFirstScan: (@MainActor (Int) -> Void)?
    /// Called after a scan that changed the state of sessions the store already had, with those
    /// changes. Never for the sessions a scan adds, so the states found at launch or by a new store
    /// never show up here (`SoundController` listens).
    @ObservationIgnored var onStateChanges: (@MainActor ([SessionStateChange]) -> Void)?

    let folder: URL
    let entrypoints: Set<String>?
    /// The external sessions folder; nil when sessions from other tools are off.
    let externalFolder: URL?
    /// Tool ids (`codex`) whose sessions are not shown (Settings > Agents).
    let hiddenTools: Set<String>
    /// Where transcripts live; the insight readers resolve their files through it.
    let locator: TranscriptLocator

    @ObservationIgnored private var watcher: RegistryWatcher?
    @ObservationIgnored private var externalWatcher: RegistryWatcher?
    @ObservationIgnored private var exitSources: [SessionKey: DispatchSourceProcess] = [:]
    @ObservationIgnored private var removalTokens: [SessionKey: UUID] = [:]
    @ObservationIgnored private var insightReaders: [SessionKey: InsightReader] = [:]
    /// A key that came back in a scan while its ended session was still fading out (an id reused
    /// right after `end`, a reused pid): the newest snapshot, added as a new session once the old one
    /// is removed, since no file event may follow to scan it again.
    @ObservationIgnored private var reappearing: [SessionKey: SessionSnapshot] = [:]
    /// Sources whose first scan has not arrived yet (`hasScanned` waits for all of them).
    @ObservationIgnored private var awaitingFirstScan: Set<Bool>

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/Wallflower/sessions`: where other tools write their session files.
    static var defaultExternalFolder: URL {
        AppInfo.supportFolder.appending(path: "sessions", directoryHint: .isDirectory)
    }

    /// The keys of every live session file in the last scans, of both sources and whatever the filter.
    var presentKeys: Set<SessionKey> {
        Set(presentPids.map(SessionKey.claude)).union(presentExternalIDs.map(SessionKey.external))
    }

    /// Whether this store watches external sessions at all.
    var watchesExternal: Bool { externalFolder != nil }

    /// - Parameters:
    ///   - entrypoints: keep only Claude sessions with one of these entrypoints; `nil` keeps all.
    ///     External sessions are never filtered by it.
    ///   - externalFolder: the external sessions folder; nil leaves sessions from other tools out.
    ///   - hiddenTools: tool ids whose external sessions are left out.
    ///   - projectsFolder: the `~/.claude/projects` folder holding the transcripts.
    init(
        folder: URL = SessionStore.defaultFolder,
        entrypoints: Set<String>? = DataTuning.defaultEntrypoints,
        externalFolder: URL? = nil,
        hiddenTools: Set<String> = [],
        projectsFolder: URL = TranscriptLocator.defaultProjectsFolder
    ) {
        self.folder = folder
        self.entrypoints = entrypoints
        self.externalFolder = externalFolder
        self.hiddenTools = hiddenTools
        locator = TranscriptLocator(projectsFolder: projectsFolder)
        // `true` is the Claude registry, `false` the external folder.
        awaitingFirstScan = externalFolder == nil ? [true] : [true, false]
    }

    /// Initial scan, then event driven updates. Calling it twice is a no-op.
    func start() {
        guard watcher == nil else { return }
        let watcher = RegistryWatcher(folder: folder, entrypoints: entrypoints) { [weak self] result in
            Task { @MainActor in self?.reconcile(result) }
        }
        self.watcher = watcher
        if let externalFolder {
            let external = RegistryWatcher.external(folder: externalFolder) { [weak self] result in
                Task { @MainActor in self?.reconcile(result) }
            }
            externalWatcher = external
            external.start()
        }
        watcher.start()
    }

    /// Cancels the watchers, every process source, every insight reader and every pending removal.
    /// Sessions stay as they are.
    func stop() {
        watcher?.stop()
        watcher = nil
        externalWatcher?.stop()
        externalWatcher = nil
        exitSources.values.forEach { $0.cancel() }
        exitSources.removeAll()
        insightReaders.values.forEach { $0.stop() }
        insightReaders.removeAll()
        removalTokens.removeAll()
        reappearing.removeAll()
    }

    /// Sort order of the panel: the one place it is decided. `acknowledgements` are the times the
    /// person opened each session's chat (`PanelModel`); an acknowledged idle period is no longer your turn.
    nonisolated static func sorted(_ sessions: [Session], acknowledgements: [SessionKey: Date] = [:], now: Date = Date()) -> [Session] {
        MainActor.assumeIsolated {
            let ranks = Dictionary(sessions.map { ($0.key, $0.sortRank(acknowledgedAt: acknowledgements[$0.key], now: now)) }, uniquingKeysWith: { first, _ in first })
            return sessions.sorted { a, b in
                let rankA = ranks[a.key] ?? 0
                let rankB = ranks[b.key] ?? 0
                if rankA != rankB { return rankA < rankB }
                if a.stateSince != b.stateSince { return a.stateSince > b.stateSince }
                return a.key < b.key
            }
        }
    }

    // MARK: Diffing

    /// Applies one scan of the Claude registry: new pids become sessions, known ones are updated in
    /// place, vanished ones are ended. Internal so tests can drive it without a folder.
    func reconcile(_ result: RegistryScanResult) {
        presentPids = result.presentPids
        merge(
            result.records.map(SessionSnapshot.init(record:)),
            present: Set(result.presentPids.map(SessionKey.claude)),
            claude: true
        )
    }

    /// Applies one scan of the external sessions folder, the same way. Sessions of a tool in
    /// `hiddenTools` (Settings > Agents, its Show switch off) are left out as if their files were not there.
    func reconcile(_ result: ExternalScanResult) {
        let records = hiddenTools.isEmpty ? result.records : result.records.filter { !hiddenTools.contains($0.tool?.lowercased() ?? "") }
        let present = hiddenTools.isEmpty ? result.presentIDs
            : result.presentIDs.subtracting(result.records.filter { hiddenTools.contains($0.tool?.lowercased() ?? "") }.map(\.id))
        presentExternalIDs = present
        merge(
            records.map(SessionSnapshot.init(external:)),
            present: Set(present.map(SessionKey.external)),
            claude: false
        )
    }

    /// One source's snapshots against the sessions of that source (`claude`); the other source's
    /// sessions are left alone.
    private func merge(_ snapshots: [SessionSnapshot], present: Set<SessionKey>, claude: Bool) {
        var byKey = Dictionary(sessions.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        reappearing = reappearing.filter { $0.key.isClaude != claude }
        var changes: [SessionStateChange] = []

        for snapshot in snapshots {
            if let session = byKey[snapshot.key] {
                // An ended session is on its way out; a reappearing key is a reused pid or id, added
                // as a new session once the old one is gone (`remove`).
                guard !session.ended else {
                    reappearing[snapshot.key] = snapshot
                    continue
                }
                let before = session.state
                session.apply(snapshot: snapshot)
                if session.state != before { changes.append(SessionStateChange(session: session, from: before, to: session.state)) }
                // The registry is rewritten after the transcript line that caused the status change,
                // so a recompute here sees the complete transcript. Cached stamps make it free otherwise.
                if let sessionId = snapshot.transcriptSessionId {
                    insightReaders[snapshot.key]?.update(cwd: snapshot.cwd, sessionId: sessionId)
                }
            } else {
                byKey[snapshot.key] = add(snapshot)
            }
        }

        let decoded = Set(snapshots.map(\.key))
        for session in sessions where session.key.isClaude == claude && !session.ended && !decoded.contains(session.key) {
            // Present but undecodable means mid-rewrite: keep it. Absent means the file is gone.
            if !present.contains(session.key) { end(session) }
        }

        resort()
        if !changes.isEmpty { onStateChanges?(changes) }
        awaitingFirstScan.remove(claude)
        if !hasScanned, awaitingFirstScan.isEmpty {
            hasScanned = true
            onFirstScan?(sessions.count)
        }
    }

    // MARK: Private

    @discardableResult
    private func add(_ snapshot: SessionSnapshot) -> Session {
        let session = Session(snapshot: snapshot)
        sessions.append(session)
        watchExit(of: session)
        startInsightReader(for: session, snapshot: snapshot)
        return session
    }

    private func resort() {
        let ordered = Self.sorted(sessions)
        if ordered.map(\.key) != sessions.map(\.key) { sessions = ordered }
    }

    /// The kernel tells us when the process exits; no liveness polling. External sessions without a
    /// pid have no process to watch: their file's TTL ends them (`RegistryWatcher.external`).
    private func watchExit(of session: Session) {
        guard let pid = session.pid else { return }
        let key = session.key
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.processDidExit(key) }
        }
        source.activate()
        exitSources[key] = source
    }

    private func processDidExit(_ key: SessionKey) {
        guard let session = sessions.first(where: { $0.key == key }) else { return }
        end(session)
    }

    /// Transcript facts arrive off the main actor and are applied here, to the session if it still
    /// exists. Claude sessions only: other tools' transcripts are unknown.
    private func startInsightReader(for session: Session, snapshot: SessionSnapshot) {
        guard let pid = session.key.claudePid, let sessionId = snapshot.transcriptSessionId else { return }
        let key = session.key
        let reader = InsightReader(pid: pid, locator: locator) { [weak self] insight in
            Task { @MainActor in self?.applyInsight(insight, to: key) }
        }
        insightReaders[key] = reader
        reader.update(cwd: snapshot.cwd, sessionId: sessionId)
    }

    private func applyInsight(_ insight: SessionInsight, to key: SessionKey) {
        guard let session = sessions.first(where: { $0.key == key }), !session.ended else { return }
        session.apply(insight: insight)
    }

    private func end(_ session: Session) {
        guard !session.ended else { return }
        session.markEnded()
        let key = session.key
        exitSources.removeValue(forKey: key)?.cancel()
        insightReaders.removeValue(forKey: key)?.stop()
        let token = UUID()
        removalTokens[key] = token
        // One-shot: lets the UI fade the row out before the session disappears from the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + DataTuning.endedLinger) { [weak self] in
            MainActor.assumeIsolated { self?.remove(key: key, token: token) }
        }
    }

    private func remove(key: SessionKey, token: UUID) {
        guard removalTokens[key] == token else { return }
        removalTokens[key] = nil
        sessions.removeAll { $0.key == key }
        if let snapshot = reappearing.removeValue(forKey: key) {
            add(snapshot)
            resort()
        }
    }
}

/// One session's state change in a scan (`SessionStore.onStateChanges`).
struct SessionStateChange {
    let session: Session
    let from: SessionState
    let to: SessionState
}
