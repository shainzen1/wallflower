import Foundation

/// Watches one session's transcript (and its subagents folder) and reports a `SessionInsight`
/// whenever the derived facts change. Event driven: vnode sources, a cancel-and-reschedule debounce
/// of `DataTuning.insightDebounce`, no timers, no polling.
///
/// Lifecycle, driven by `SessionStore`:
/// - `update(cwd:sessionId:)` on every registry apply. A new (cwd, sessionId) re-locates the files
///   (session ids rotate on resume); the same pair just schedules a recompute, which is what the
///   registry status change needs: Claude Code appends the transcript line first and rewrites the
///   registry file 2 to 4 ms later (verified 13-10-26 on two idle sessions: transcript mtime .102,
///   registry `statusUpdatedAt` .104; .891 vs .894), so by the time the store sees the status the
///   transcript is complete, and the transcript's own vnode event usually got there first anyway.
/// - `stop()` when the session ends.
///
/// Watching: an `O_EVTONLY` source on the transcript file, and one on the subagents folder (files
/// appearing there: the folder itself does not report appends to agent transcripts, but a subagent's
/// completion writes `agent-<id>.prefix.json` and the parent transcript gets a notification line, both
/// of which fire). While the transcript or the folder does not exist yet, their parent folders are
/// watched and the sources are installed as soon as they appear.
///
/// Cost: the transcript facts are cached by file size and mtime, subagent verdicts per file the same
/// way, so an event that changed nothing is a few stats. One computation reads at most
/// `DataTuning.transcriptTailBytes` plus the tails of the live subagents.
///
/// All mutable state is confined to `queue`, shared by every reader (computations are short).
final class InsightReader: @unchecked Sendable {
    typealias Handler = @Sendable (SessionInsight) -> Void

    let pid: pid_t
    private let locator: TranscriptLocator
    private let onInsight: Handler
    private static let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).insight", qos: .utility)
    private var queue: DispatchQueue { Self.queue }

    // Queue-confined state.
    private var cwd = ""
    private var sessionId = ""
    private var transcriptURL: URL?
    private var subagentsFolder: URL?
    private var transcriptSource: DispatchSourceFileSystemObject?
    private var subagentsSource: DispatchSourceFileSystemObject?
    private var discoverySources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingCompute: DispatchWorkItem?
    private var isStopped = false
    private var transcriptStamp: FileStamp?
    private var facts = TranscriptFacts()
    private var subagentCache: [String: SubagentScanner.Verdict] = [:]
    private var lastInsight: SessionInsight?
    private var loggedCost = false

    private static var eventMask: DispatchSource.FileSystemEvent { [.write, .extend, .attrib, .delete, .rename, .revoke] }
    private static var goneMask: DispatchSource.FileSystemEvent { [.delete, .rename, .revoke] }

    init(pid: pid_t, locator: TranscriptLocator, onInsight: @escaping Handler) {
        self.pid = pid
        self.locator = locator
        self.onInsight = onInsight
    }

    /// Points the reader at the session's current files and schedules a computation.
    func update(cwd: String, sessionId: String) {
        queue.async { [self] in
            guard !isStopped else { return }
            if cwd != self.cwd || sessionId != self.sessionId {
                relocate(cwd: cwd, sessionId: sessionId)
            }
            scheduleCompute()
        }
    }

    /// Cancels every source and pending computation. Safe to call more than once.
    func stop() {
        queue.async { [self] in
            isStopped = true
            pendingCompute?.cancel()
            pendingCompute = nil
            transcriptSource?.cancel()
            transcriptSource = nil
            subagentsSource?.cancel()
            subagentsSource = nil
            discoverySources.values.forEach { $0.cancel() }
            discoverySources.removeAll()
        }
    }

    // MARK: Queue-confined

    private func relocate(cwd: String, sessionId: String) {
        self.cwd = cwd
        self.sessionId = sessionId
        transcriptURL = locator.transcriptURL(cwd: cwd, sessionId: sessionId)
        subagentsFolder = locator.subagentsFolder(cwd: cwd, sessionId: sessionId)
        transcriptStamp = nil
        facts = TranscriptFacts()
        subagentCache.removeAll()
        discoverySources.values.forEach { $0.cancel() }
        discoverySources.removeAll()
        watchTranscript()
        watchSubagents()
    }

    private func watchTranscript() {
        transcriptSource?.cancel()
        transcriptSource = nil
        guard let transcriptURL else { return }
        transcriptSource = makeSource(path: transcriptURL.path) { [weak self] flags in
            self?.transcriptDidChange(flags)
        }
        if transcriptSource == nil {
            watchForAppearance(of: transcriptURL)
        }
    }

    private func transcriptDidChange(_ flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: Self.goneMask) {
            watchTranscript()
        }
        scheduleCompute()
    }

    private func watchSubagents() {
        subagentsSource?.cancel()
        subagentsSource = nil
        guard let subagentsFolder else { return }
        subagentsSource = makeSource(path: subagentsFolder.path) { [weak self] flags in
            self?.subagentsDidChange(flags)
        }
        if subagentsSource == nil {
            watchForAppearance(of: subagentsFolder)
        }
    }

    private func subagentsDidChange(_ flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: Self.goneMask) {
            watchSubagents()
        }
        scheduleCompute()
    }

    /// Watches the nearest existing ancestor of `url`; on any event there, retries both watchers.
    private func watchForAppearance(of url: URL) {
        var folder = url.deletingLastPathComponent()
        while access(folder.path, F_OK) != 0 {
            let parent = folder.deletingLastPathComponent()
            guard parent.path != folder.path else { return }
            folder = parent
        }
        let path = folder.path
        guard discoverySources[path] == nil else { return }
        discoverySources[path] = makeSource(path: path) { [weak self] _ in
            self?.ancestorDidChange()
        }
    }

    /// Something appeared or vanished in a watched ancestor: install the real sources if the files
    /// exist now, otherwise move the discovery one level closer (a new intermediate folder).
    private func ancestorDidChange() {
        if transcriptSource == nil { watchTranscript() }
        if subagentsSource == nil { watchSubagents() }
        if transcriptSource != nil, subagentsSource != nil {
            discoverySources.values.forEach { $0.cancel() }
            discoverySources.removeAll()
        }
        scheduleCompute()
    }

    private func scheduleCompute() {
        guard !isStopped else { return }
        pendingCompute?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.compute() }
        pendingCompute = item
        queue.asyncAfter(deadline: .now() + DataTuning.insightDebounce, execute: item)
    }

    private func compute() {
        guard !isStopped else { return }
        pendingCompute = nil
        guard let transcriptURL, let subagentsFolder else { return }

        let stamp = FileStamp(path: transcriptURL.path)
        if stamp == nil {
            transcriptStamp = nil
            facts = TranscriptFacts()
            if transcriptSource == nil { watchForAppearance(of: transcriptURL) }
        } else if stamp != transcriptStamp {
            let clock = ContinuousClock()
            let start = clock.now
            var bytes = 0
            if let tail = try? TranscriptTail.read(url: transcriptURL, maxBytes: DataTuning.transcriptTailBytes) {
                bytes = tail.data.count
                facts = TranscriptTail.facts(from: tail.data, startsMidFile: tail.startsMidFile)
            }
            transcriptStamp = stamp
            if DataTuning.logInsights, !loggedCost {
                loggedCost = true
                let elapsed = clock.now - start
                NSLog("insight cost pid=%d bytes=%d lines=%d took=%@", pid, bytes, facts.scannedLines, "\(elapsed)")
            }
        }
        if subagentsSource == nil, access(subagentsFolder.path, F_OK) == 0 { watchSubagents() }
        let live = SubagentScanner.liveCount(in: subagentsFolder, tailBytes: DataTuning.subagentTailBytes, cache: &subagentCache)

        let insight = SessionInsight(
            activity: facts.activity(liveSubagents: live),
            subagentCount: live,
            gitBranch: facts.gitBranch ?? GitHeadReader.branch(cwd: cwd),
            lastToolFailed: facts.lastResultFailed
        )
        guard insight != lastInsight else { return }
        lastInsight = insight
        if DataTuning.logInsights {
            NSLog("insight pid=%d activity=%@ subagents=%d branch=%@ failed=%d",
                  pid, insight.activity.rawValue, insight.subagentCount, insight.gitBranch ?? "-", insight.lastToolFailed ? 1 : 0)
        }
        onInsight(insight)
    }

    private func makeSource(
        path: String,
        handler: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: Self.eventMask, queue: queue)
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.setCancelHandler { close(fd) }
        source.activate()
        return source
    }
}
