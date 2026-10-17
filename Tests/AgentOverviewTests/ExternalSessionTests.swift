import Foundation
import Testing
@testable import AgentOverview

/// The external sessions format (`docs/external-sessions.md`): decoding, liveness, identity, the
/// store mixing both sources, the detail line and the click routes.
@Suite("External sessions: format")
struct ExternalSessionFormatTests {
    private func decode(_ json: String) -> ExternalSessionRecord? {
        ExternalSessionScanner.decode(Data(json.utf8))
    }

    @Test func fullFixtureDecodesEveryField() throws {
        let record = try #require(ExternalSessionScanner.decode(TestSupport.externalFixtureData("codex-full")))
        #expect(record.id == "codex-7f3a")
        #expect(record.tool == "codex")
        #expect(record.name == "Port the parser")
        #expect(record.cwd == "/Users/demo/Developer/project-e")
        #expect(record.status == .waiting)
        #expect(record.waitingKind == .permission)
        #expect(record.pid == 15702)
        #expect(record.updatedAt == 1_791_884_300_000)
        #expect(record.statusUpdatedAt == 1_791_884_290_000)
        #expect(record.startedAt == 1_791_884_000_000)
        #expect(record.open == .url(URL(string: "https://example.com/sessions/codex-7f3a")!))
        #expect(record.statusUpdatedDate == Date(timeIntervalSince1970: 1_791_884_290))
        #expect(record.startedDate == Date(timeIntervalSince1970: 1_791_884_000))

        let snapshot = SessionSnapshot(external: record)
        #expect(snapshot.key == .external("codex-7f3a"))
        #expect(snapshot.pid == 15702)
        #expect(snapshot.source == .external(tool: "codex"))
        #expect(snapshot.state == .needsInput(kind: .permission))
        #expect(snapshot.name == "Port the parser")
        #expect(snapshot.transcriptSessionId == nil, "no Claude transcript for other tools")
        #expect(snapshot.hostSessionId == nil)
    }

    @Test func missingOptionalFieldsFallBack() throws {
        let record = try #require(ExternalSessionScanner.decode(TestSupport.externalFixtureData("minimal")))
        #expect(record.id == "minimal-1" && record.status == .busy)
        #expect(record.tool == nil && record.name == nil && record.cwd == nil && record.pid == nil)
        #expect(record.updatedAt == nil && record.startedAt == nil && record.open == nil && record.waitingFor == nil)
        #expect(SessionSnapshot(external: record).name == "minimal-1", "no name, folder or tool: the id")
        #expect(SessionSnapshot(external: record).source == .external(tool: ""))

        let inFolder = try #require(decode(#"{"id": "a", "status": "idle", "cwd": "/Users/demo/Developer/project-h"}"#))
        #expect(SessionSnapshot(external: inFolder).name == "project-h", "no name: the folder, like Claude sessions")
        let toolOnly = try #require(decode(#"{"id": "a", "status": "idle", "tool": "codex"}"#))
        #expect(SessionSnapshot(external: toolOnly).name == "codex session")
        let blankName = try #require(decode(#"{"id": "a", "status": "idle", "name": "   ", "cwd": "/Users/demo/x"}"#))
        #expect(SessionSnapshot(external: blankName).name == "x")

        // Without updatedAt or startedAt the file's own dates stand in.
        var dated = toolOnly
        let modified = Date(timeIntervalSince1970: 1_791_884_000)
        dated.fileModified = modified
        dated.fileCreated = modified.addingTimeInterval(-60)
        #expect(dated.freshness == modified)
        #expect(dated.statusUpdatedDate == modified)
        #expect(dated.startedDate == modified.addingTimeInterval(-60))
    }

    @Test func unknownKeysAreIgnoredAndWrongTypesAreAbsent() throws {
        let record = try #require(ExternalSessionScanner.decode(TestSupport.externalFixtureData("unknown-keys")))
        #expect(record.id == "gemini-42" && record.tool == "gemini" && record.status == .idle)
        #expect(record.pid == nil, "a pid that is not a number is no pid")
        #expect(record.open == .app(bundleID: "com.example.Terminal"), "unknown keys inside open are ignored too")

        #expect(decode(#"{"id": "a", "status": "busy", "pid": 0}"#)?.pid == nil, "pid 0 is no process")
        #expect(decode(#"{"id": "a", "status": "busy", "pid": -4}"#)?.pid == nil)
        #expect(decode(#"{"id": "a", "status": "busy", "updatedAt": 1.7918843e12}"#)?.updatedAt == 1_791_884_300_000, "a whole float is a time")
        #expect(decode(#"{"id": "a", "status": "busy", "name": 12}"#)?.name == nil)
    }

    @Test func malformedFilesDoNotDecode() throws {
        #expect(ExternalSessionScanner.decode(try TestSupport.externalFixtureData("malformed")) == nil)
        #expect(decode(#"{"status": "busy"}"#) == nil, "id is required")
        #expect(decode(#"{"id": "  ", "status": "busy"}"#) == nil, "a blank id is no id")
        #expect(decode(#"{"id": 7, "status": "busy"}"#) == nil)
        #expect(decode(#"{"id": "a"}"#) == nil, "status is required")
        #expect(decode(#"{"id": "a", "status": "done"}"#) == nil, "only busy, idle and waiting")
        #expect(decode(#"["id", "a"]"#) == nil)
    }

    @Test func waitingForMapsToTheExistingKinds() {
        #expect(decode(#"{"id": "a", "status": "waiting", "waitingFor": "question"}"#)?.waitingKind == .question)
        #expect(decode(#"{"id": "a", "status": "waiting", "waitingFor": "Permission"}"#)?.waitingKind == .permission)
        #expect(decode(#"{"id": "a", "status": "waiting", "waitingFor": "a dialog"}"#)?.waitingKind == .other)
        #expect(decode(#"{"id": "a", "status": "waiting"}"#)?.waitingKind == .other)
        #expect(WaitingKind(waitingFor: "question") == .other, "the Claude registry keeps its own strings")
    }

    @Test func openTakesOneOfURLAppCommand() throws {
        #expect(decode(#"{"id": "a", "status": "busy", "open": {"url": "vscode://file/x"}}"#)?.open == .url(URL(string: "vscode://file/x")!))
        #expect(decode(#"{"id": "a", "status": "busy", "open": {"app": "com.example.Editor"}}"#)?.open == .app(bundleID: "com.example.Editor"))
        #expect(decode(#"{"id": "a", "status": "busy", "open": {"command": "tmux attach -t a"}}"#)?.open == .command("tmux attach -t a"))
        #expect(
            decode(#"{"id": "a", "status": "busy", "open": {"command": "x", "app": "com.example.A", "url": "https://example.com"}}"#)?.open
                == .url(URL(string: "https://example.com")!),
            "url wins over app over command"
        )
        #expect(decode(#"{"id": "a", "status": "busy", "open": {"url": "no scheme", "app": "com.example.A"}}"#)?.open == .app(bundleID: "com.example.A"))
        #expect(decode(#"{"id": "a", "status": "busy", "open": {}}"#)?.open == nil)
        #expect(decode(#"{"id": "a", "status": "busy", "open": "https://example.com"}"#)?.open == nil, "open is an object")
        #expect(decode(#"{"id": "a", "status": "busy", "open": {"command": "  "}}"#)?.open == nil)
    }
}

@Suite("External sessions: scanner and liveness")
struct ExternalSessionScannerTests {
    @Test func scansLiveFilesAndSkipsMalformedOnes() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        let fresh = TestSupport.millis(now)
        try TestSupport.writeExternal(["id": "a", "tool": "codex", "status": "busy", "pid": Int(TestSupport.livePid)], to: folder)
        try TestSupport.writeExternal(["id": "b", "status": "idle", "updatedAt": fresh], to: folder)
        try Data("{ not json".utf8).write(to: folder.appending(path: "broken.json"))
        try Data("{}".utf8).write(to: folder.appending(path: "notes.txt"))
        try Data(#"{"id": "hidden", "status": "busy"}"#.utf8).write(to: folder.appending(path: ".hidden.json"))

        let result = ExternalSessionScanner.scan(folder: folder, now: now)
        #expect(result.records.map(\.id) == ["a", "b"])
        #expect(result.presentIDs == ["a", "b", "broken"], "a fresh undecodable file is mid-rewrite, not gone")
        #expect(result.fileURLs.count == 3, "every .json is watched, the broken one too")
        #expect(result.records[0].fileModified != nil && result.records[0].fileCreated != nil)
    }

    @Test func withAPidTheProcessDecides() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = TestSupport.millis(Date().addingTimeInterval(-86_400))
        try TestSupport.writeExternal(["id": "alive", "status": "busy", "pid": Int(TestSupport.livePid), "updatedAt": old], to: folder)
        try TestSupport.writeExternal(["id": "dead", "status": "busy", "pid": Int(TestSupport.deadPid), "updatedAt": TestSupport.millis(Date())], to: folder)
        let result = ExternalSessionScanner.scan(folder: folder)
        #expect(result.records.map(\.id) == ["alive"], "an old write with a live pid lives; a fresh one with a dead pid does not")
        #expect(result.presentIDs == ["alive"])
        #expect(result.nextExpiry == nil, "no TTL for sessions with a pid")
    }

    @Test func withoutAPidTheTTLDecides() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date().addingTimeInterval(3600)  // an hour ahead, so the files' own dates are old
        let ttl: TimeInterval = 600
        try TestSupport.writeExternal(["id": "fresh", "status": "busy", "updatedAt": TestSupport.millis(now.addingTimeInterval(-60))], to: folder)
        try TestSupport.writeExternal(["id": "older", "status": "busy", "updatedAt": TestSupport.millis(now.addingTimeInterval(-300))], to: folder)
        try TestSupport.writeExternal(["id": "stale", "status": "busy", "updatedAt": TestSupport.millis(now.addingTimeInterval(-601))], to: folder)
        let result = ExternalSessionScanner.scan(folder: folder, now: now, ttl: ttl)
        #expect(result.records.map(\.id) == ["fresh", "older"])
        #expect(result.presentIDs == ["fresh", "older"])
        let expiry = try #require(result.nextExpiry)
        #expect(abs(expiry.timeIntervalSince(now.addingTimeInterval(300))) < 0.01, "the oldest live record expires first")
    }

    @Test func touchingTheFileRefreshesAnOldUpdatedAt() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = TestSupport.millis(Date().addingTimeInterval(-3600))
        let url = try TestSupport.writeExternal(["id": "touched", "status": "idle", "updatedAt": old], to: folder)
        #expect(ExternalSessionScanner.scan(folder: folder).records.map(\.id) == ["touched"], "just written: the file is fresh")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        #expect(ExternalSessionScanner.scan(folder: folder).records.isEmpty, "both an hour old: ended")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        #expect(ExternalSessionScanner.scan(folder: folder).records.map(\.id) == ["touched"], "a touch keeps it alive")
    }

    @Test func twoFilesWithOneIDKeepTheNewest() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        try TestSupport.writeExternal(["id": "same", "name": "Newer", "status": "busy", "updatedAt": TestSupport.millis(now.addingTimeInterval(5))], to: folder)
        let copy = folder.appending(path: "copy.json")
        try JSONSerialization.data(withJSONObject: ["id": "same", "name": "Older", "status": "busy", "updatedAt": TestSupport.millis(now)])
            .write(to: copy)
        let result = ExternalSessionScanner.scan(folder: folder, now: now)
        #expect(result.records.map(\.name) == ["Newer"])
    }

    @Test func missingFolderIsEmpty() {
        let result = ExternalSessionScanner.scan(folder: URL(filePath: "/nonexistent/wallflower-sessions"))
        #expect(result == ExternalScanResult())
    }
}

@Suite("External sessions: identity")
@MainActor
struct ExternalSessionIdentityTests {
    private func makeDefaults() -> UserDefaults {
        let name = "ExternalIdentity-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func keysNeverCollideAcrossSources() {
        #expect(SessionKey.claude(1) != SessionKey.external("1"))
        #expect(SessionKey.claude(42).description == "42", "Claude stack ids stay as they were")
        #expect(SessionKey.external("42").description == "x:42")
        #expect(Set([SessionKey.claude(7), .external("7"), .claude(7)]).count == 2)
        #expect([SessionKey.external("b"), .claude(9), .external("a"), .claude(3)].sorted() == [.claude(3), .claude(9), .external("a"), .external("b")])
        #expect(SessionKey.claude(5).claudePid == 5 && SessionKey.external("5").claudePid == nil)
    }

    @Test func faceSeedsStayForClaudeAndUseTheIDForExternal() {
        #expect(SessionRow.seed(key: .claude(12), hostSessionId: nil) == "pid-12")
        #expect(SessionRow.seed(key: .claude(12), hostSessionId: "local_x") == "local_x")
        #expect(SessionRow.seed(key: .external("codex-1"), hostSessionId: nil) == "external-codex-1")
    }

    @Test func hiddenSessionsStoreBothKindsAndReadOldLists() {
        let defaults = makeDefaults()
        let started = Date(timeIntervalSince1970: 1_791_879_441.228)
        let hidden = HiddenSessions(defaults: defaults)
        hidden.hide(key: .claude(4242), startedAt: started)
        hidden.hide(key: .external("codex-1"), startedAt: started)
        hidden.hide(key: .external("4242"), startedAt: nil)

        let reloaded = HiddenSessions(defaults: defaults)
        #expect(reloaded.entries == [
            .init(key: .claude(4242), startedAt: 1_791_879_441_228),
            .init(key: .external("codex-1"), startedAt: 1_791_879_441_228),
            .init(key: .external("4242"), startedAt: nil),
        ])
        #expect(reloaded.contains(key: .external("codex-1"), startedAt: started))
        #expect(!reloaded.contains(key: .external("codex-1"), startedAt: started.addingTimeInterval(1)), "a new session under an old id shows")
        #expect(reloaded.contains(key: .external("4242"), startedAt: .now))
        let raw = defaults.array(forKey: HiddenSessions.key) as? [[String: Any]]
        #expect(raw?[1]["external"] as? String == "codex-1")
        #expect(raw?[0]["pid"] as? Int == 4242)
    }

    @Test func pruneKeepsExternalEntriesWhileTheStoreDoesNotWatchThem() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let hidden = HiddenSessions(defaults: makeDefaults())
        hidden.hide(key: .claude(1), startedAt: started)
        hidden.hide(key: .external("gone"), startedAt: started)
        hidden.hide(key: .external("other"), startedAt: started)
        hidden.prune(keeping: [], otherKeys: [], keepsExternal: true)
        #expect(hidden.entries.map(\.key) == [.external("gone"), .external("other")], "sessions from other tools are off: nothing known about them")
        hidden.prune(keeping: [(key: .external("other"), startedAt: started)])
        #expect(hidden.entries.map(\.key) == [.external("other")])
    }
}

@Suite("External sessions: store")
@MainActor
struct ExternalSessionStoreTests {
    private func claudeRecord(_ fixture: String, pid: pid_t, since: Date) throws -> SessionRecord {
        var record = try TestSupport.fixtureRecord(fixture)
        record.pid = pid
        record.statusUpdatedAt = TestSupport.millis(since)
        return record
    }

    private func external(_ id: String, tool: String = "codex", status: RegistryStatus, waitingFor: String? = nil, since: Date) -> ExternalSessionRecord {
        ExternalSessionRecord(
            id: id, tool: tool, cwd: "/Users/demo/Developer/\(id)", status: status, waitingFor: waitingFor,
            updatedAt: TestSupport.millis(since), statusUpdatedAt: TestSupport.millis(since)
        )
    }

    private func externalScan(_ records: [ExternalSessionRecord]) -> ExternalScanResult {
        ExternalScanResult(records: records, presentIDs: Set(records.map(\.id)))
    }

    @Test func reconcileMixesBothSourcesAndEachEndsOnlyItsOwn() async throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/nonexistent-external"))
        defer { store.stop() }
        var firstScans: [Int] = []
        store.onFirstScan = { firstScans.append($0) }
        let now = Date()
        let claude = try claudeRecord("busy-desktop", pid: TestSupport.livePid, since: now.addingTimeInterval(-60))
        store.reconcile(RegistryScanResult(records: [claude], presentPids: [claude.pid]))
        #expect(!store.hasScanned, "the external folder's first scan is still due")
        #expect(firstScans.isEmpty)

        store.reconcile(externalScan([external("codex-1", status: .busy, since: now.addingTimeInterval(-30))]))
        #expect(store.hasScanned && firstScans == [2])
        #expect(store.sessions.map(\.key) == [.external("codex-1"), .claude(TestSupport.livePid)], "both working: the newer change first")
        let codex = try #require(store.sessions.first)
        #expect(codex.source == .external(tool: "codex") && codex.pid == nil)

        // A Claude scan without external records leaves the external session alone, and the other way round.
        store.reconcile(RegistryScanResult(records: [claude], presentPids: [claude.pid]))
        store.reconcile(externalScan([external("codex-1", status: .busy, since: now.addingTimeInterval(-30))]))
        #expect(store.sessions.count == 2 && !store.sessions.contains { $0.ended })

        // The external session finishes: the same done moment as a Claude session.
        store.reconcile(externalScan([external("codex-1", status: .idle, since: now)]))
        #expect(codex.state == .idle && codex.isJustFinished())
        #expect(store.presentKeys == [.claude(TestSupport.livePid), .external("codex-1")])

        // Its file goes: it ends and leaves after the linger; the Claude session stays.
        store.reconcile(externalScan([]))
        #expect(codex.ended)
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 1) { store.sessions.count == 1 })
        #expect(store.sessions.first?.key == .claude(TestSupport.livePid))
        #expect(firstScans == [2], "the first scan is reported once")
    }

    @Test func midRewriteKeepsTheExternalSession() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/nonexistent-external"))
        defer { store.stop() }
        store.reconcile(externalScan([external("a", status: .busy, since: Date())]))
        store.reconcile(ExternalScanResult(records: [], presentIDs: ["a"]))
        #expect(store.sessions.count == 1 && store.sessions.first?.ended == false)
    }

    @Test func anIDReusedWhileTheOldSessionFadesShowsAfterIt() async throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/x"))
        defer { store.stop() }
        let first = external("same", status: .busy, since: Date().addingTimeInterval(-60))
        store.reconcile(externalScan([first]))
        let old = try #require(store.sessions.first)
        store.reconcile(externalScan([]))
        #expect(old.ended)
        var second = external("same", status: .idle, since: Date())
        second.startedAt = TestSupport.millis(Date())
        store.reconcile(externalScan([second]))
        #expect(store.sessions.count == 1 && store.sessions[0] === old, "the old face fades out first")
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 1) { store.sessions.first.map { $0 !== old } ?? false })
        let new = try #require(store.sessions.first)
        #expect(!new.ended && new.state == .idle && new.key == .external("same"), "no further scan needed")

        // Gone from the folder again before the linger ends: nothing comes back.
        store.reconcile(externalScan([]))
        store.reconcile(externalScan([external("same", status: .busy, since: Date())]))
        store.reconcile(externalScan([]))
        try await Task.sleep(for: .seconds(DataTuning.endedLinger + 0.3))
        #expect(store.sessions.isEmpty)
    }

    @Test func sortingTreatsBothSourcesAlike() throws {
        let now = Date()
        let sessions = try [
            Session(snapshot: SessionSnapshot(record: claudeRecord("idle-desktop", pid: 10, since: now.addingTimeInterval(-7200)))),
            Session(snapshot: SessionSnapshot(external: external("x-working", status: .busy, since: now.addingTimeInterval(-50)))),
            Session(snapshot: SessionSnapshot(record: claudeRecord("busy-desktop", pid: 11, since: now.addingTimeInterval(-10)))),
            Session(snapshot: SessionSnapshot(external: external("x-waiting", status: .waiting, waitingFor: "question", since: now.addingTimeInterval(-900)))),
            Session(snapshot: SessionSnapshot(external: external("x-yourturn", status: .idle, since: now.addingTimeInterval(-120)))),
            Session(snapshot: SessionSnapshot(external: external("x-idle", status: .idle, since: now.addingTimeInterval(-3600)))),
        ]
        let ordered = SessionStore.sorted(sessions, now: now).map(\.key)
        #expect(ordered == [.external("x-waiting"), .claude(11), .external("x-working"), .external("x-yourturn"), .external("x-idle"), .claude(10)])
        // Your turn and its acknowledgement work for an external session too.
        #expect(sessions[4].idleTier(acknowledgedAt: nil, now: now) == .yourTurn)
        #expect(sessions[4].idleTier(acknowledgedAt: now, now: now) == .idle)
        #expect(sessions[4].sortRank(acknowledgedAt: now, now: now) == sessions[5].sortRank(acknowledgedAt: nil, now: now))
    }

    @Test func showSessionsFromFiltersClaudeOnly() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: DataTuning.desktopEntrypoints, externalFolder: URL(filePath: "/x"))
        defer { store.stop() }
        store.reconcile(externalScan([external("a", status: .busy, since: Date())]))
        store.reconcile(RegistryScanResult(records: [], presentPids: []))
        #expect(store.sessions.map(\.key) == [.external("a")], "the entrypoint filter never applies to other tools")
    }

    @Test func rowsShowTheToolAndTheProjectColourOfTheFolder() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/x"))
        defer { store.stop() }
        // Whole seconds: the file keeps milliseconds, so a fractional date would land a hair short of "1h 5m".
        let since = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 125)
        var waiting = external("perm", tool: "gemini", status: .waiting, waitingFor: "permission", since: since)
        waiting.cwd = nil
        store.reconcile(externalScan([external("codex-1", status: .busy, since: since), waiting]))
        store.reconcile(RegistryScanResult())
        let model = PanelModel(store: store)
        let rows = model.rows
        let perm = try #require(rows.first { $0.key == .external("perm") })
        let codex = try #require(rows.first { $0.key == .external("codex-1") })
        #expect(perm.label == "Needs permission" && perm.tool == "gemini")
        #expect(codex.label == "Working" && codex.tool == "codex", "no activity: other tools' transcripts are unknown")
        #expect(StateDurationText.text(tool: codex.tool, label: codex.label, since: codex.stateSince, now: since.addingTimeInterval(125)) == "codex · Working · 2m")
        #expect(StateDurationText.text(tool: perm.tool, label: perm.label, since: perm.stateSince, now: since.addingTimeInterval(3900)) == "gemini · Needs permission · 1h 5m")
        #expect(codex.projectKey == "codex-1", "the folder's last component, like Claude sessions")
        #expect(perm.projectKey == "gemini", "no folder: the tool")
        #expect(codex.seed == "external-codex-1")
        #expect(rows.map(\.key) == [.external("perm"), .external("codex-1")])

        #expect(SessionRow.label(for: .working, activity: .coding) == "Working · Coding", "Claude labels are unchanged")
        #expect(SessionRow.label(for: .working, activity: .coding, source: .external(tool: "")) == "Working")
        let claude = SessionRow(pid: 3, name: "c", status: .working, stateSince: since, hostSessionId: nil, ended: false, activity: .coding)
        #expect(claude.tool == nil)
        #expect(StateDurationText.text(tool: claude.tool, label: claude.label, since: since, now: since.addingTimeInterval(125)) == "Working · Coding · 2m")
    }

    @Test func externalRowsHoverAcknowledgeAndThrowLikeAnyOther() throws {
        let suite = "ExternalThrow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/x"))
        defer { store.stop() }
        store.reconcile(externalScan([external("a", status: .idle, since: Date().addingTimeInterval(-30))]))
        store.reconcile(RegistryScanResult())
        let hidden = HiddenSessions(defaults: defaults)
        let model = PanelModel(store: store, hiddenSessions: hidden)
        var opened: [SessionKey] = []
        model.open = { opened.append($0.key) }
        model.hover(rowIndex: 0)
        #expect(model.hoveredKey == .external("a"))
        #expect(model.rows[0].status.isYourTurn)
        model.tapped(model.rows[0])
        #expect(opened == [.external("a")])
        #expect(model.acknowledgements.time(for: .external("a")) != nil)
        #expect(!model.rows[0].status.isYourTurn, "clicked: seen")

        model.hideSession(key: .external("a"))
        #expect(model.rows.isEmpty && hidden.count == 1)
        model.pruneHiddenSessions()
        #expect(hidden.count == 1, "still in the folder: still hidden")
    }
}

@Suite("External sessions: opener")
struct ExternalSessionOpenerTests {
    private func row(_ opener: ExternalOpener?, pid: pid_t? = nil, cwd: String = "/Users/demo/Developer/project-g") -> SessionRow {
        SessionRow(
            key: .external("opencode-9"), pid: pid, source: .external(tool: "opencode"), opener: opener, cwd: cwd,
            name: "x", status: .working, stateSince: .now, hostSessionId: nil, ended: false, entrypoint: ""
        )
    }

    @Test func externalSessionsFollowTheirOpen() {
        let url = URL(string: "https://example.com/s/9")!
        #expect(SessionOpener.route(for: row(.url(url))) == .url(url))
        #expect(SessionOpener.route(for: row(.app(bundleID: "com.example.Editor"), pid: 99)) == .app(bundleID: "com.example.Editor"), "open wins over the pid")
        #expect(SessionOpener.route(for: row(.command("tmux attach -t 'opencode 9'"))) == .command(
            script: "#!/bin/zsh\ncd '/Users/demo/Developer/project-g' || exit 1\ntmux attach -t 'opencode 9'\n",
            fileName: "open-x-opencode-9.command"
        ))
        #expect(SessionOpener.route(for: row(.command("htop"), cwd: "")) == .command(script: "#!/bin/zsh\nhtop\n", fileName: "open-x-opencode-9.command"))
        #expect(SessionOpener.route(for: row(nil, pid: 99)) == .hostApp(pid: 99, fallsBackToClaude: false), "no open: the app hosting the pid")
        #expect(SessionOpener.route(for: row(nil)) == .nothing)
        #expect(SessionOpener.deepLink(for: row(.url(url))) == nil, "never a Claude link")
    }

    @Test func commandScriptQuotesTheFolder() {
        #expect(SessionOpener.commandScript(command: "ls", cwd: "/Users/demo/it's here") == "#!/bin/zsh\ncd '/Users/demo/it'\\''s here' || exit 1\nls\n")
    }

    @Test func claudeRoutesAreUnchanged() throws {
        let desktop = SessionRow(pid: 5, name: "a", status: .working, stateSince: .now, hostSessionId: "local_abc", ended: false)
        #expect(SessionOpener.route(for: desktop) == .claudeDeepLink(URL(string: "claude://code/continue?session=local_abc")!))
        let terminal = SessionRow(pid: 6, name: "b", status: .working, stateSince: .now, hostSessionId: nil, ended: false, entrypoint: "cli")
        #expect(SessionOpener.route(for: terminal) == .hostApp(pid: 6, fallsBackToClaude: true))
        let orphan = SessionRow(pid: 7, name: "c", status: .working, stateSince: .now, hostSessionId: nil, ended: false)
        #expect(SessionOpener.route(for: orphan) == .claudeApp)
    }
}

@Suite("External sessions: watcher end to end", .serialized)
@MainActor
struct ExternalSessionWatcherTests {
    @Test func storeFollowsFilesWrittenInPlaceAndDeleted() async throws {
        let registry = try TestSupport.makeTempFolder()
        let folder = try TestSupport.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = SessionStore(folder: registry, entrypoints: nil, externalFolder: folder, projectsFolder: registry)
        defer { store.stop() }
        store.start()
        #expect(await TestSupport.waitUntil { store.hasScanned })

        var object: [String: Any] = ["id": "codex-1", "tool": "codex", "status": "busy", "pid": Int(TestSupport.livePid), "cwd": "/Users/demo/Developer/p"]
        let file = try TestSupport.writeExternal(object, to: folder)
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        #expect(session.key == .external("codex-1") && session.state == .working)

        object["status"] = "waiting"
        object["waitingFor"] = "question"
        try TestSupport.writeExternal(object, to: folder)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.state == .needsInput(kind: .question) }, "an in-place rewrite is seen")

        // Atomic replace (what the helper script does): a new inode under the same name.
        object["status"] = "idle"
        let temp = folder.appending(path: ".codex-1.json.tmp")
        try JSONSerialization.data(withJSONObject: object).write(to: temp)
        #expect(rename(temp.path, file.path) == 0)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.state == .idle })

        try FileManager.default.removeItem(at: file)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.ended })
    }

    @Test func processExitEndsAnExternalSession() async throws {
        let registry = try TestSupport.makeTempFolder()
        let folder = try TestSupport.makeTempFolder()
        defer {
            try? FileManager.default.removeItem(at: registry)
            try? FileManager.default.removeItem(at: folder)
        }
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sleep")
        helper.arguments = ["30"]
        try helper.run()
        let store = SessionStore(folder: registry, entrypoints: nil, externalFolder: folder, projectsFolder: registry)
        defer { store.stop() }
        try TestSupport.writeExternal(["id": "wrapped", "status": "busy", "pid": Int(helper.processIdentifier)], to: folder)
        store.start()
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        helper.terminate()
        #expect(await TestSupport.waitUntil(timeout: 1) { session.ended }, "the kernel reports the exit; the file is still there")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "wrapped.json").path))
    }

    @Test func aPidlessRecordExpiresWithoutAnyFileEvent() async throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestSupport.writeExternal(["id": "short", "status": "busy", "updatedAt": TestSupport.millis(Date())], to: folder)
        let scans = ScanLog()
        let watcher = RegistryWatcher.external(folder: folder, ttl: 0.5) { result in scans.append(result.records.map(\.id)) }
        defer { watcher.stop() }
        watcher.start()
        #expect(await TestSupport.waitUntil(timeout: 1) { scans.all.first == ["short"] })
        // TTL 0.5 s plus `DataTuning.expiryRescanSlack`: one rescan, no polling, finds it expired.
        #expect(await TestSupport.waitUntil(timeout: 0.5 + DataTuning.expiryRescanSlack + 1.5) { scans.all.last == [] })
        let count = scans.all.count
        try await Task.sleep(for: .milliseconds(1500))
        #expect(scans.all.count == count, "nothing left to expire: no further scans")
    }
}

/// Scan results collected off the main actor.
private final class ScanLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [[String]] = []

    func append(_ ids: [String]) {
        lock.lock()
        entries.append(ids)
        lock.unlock()
    }

    var all: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

@Suite("External sessions: settings")
@MainActor
struct ExternalSessionSettingsTests {
    @Test func onByDefaultStoredAndScriptable() {
        let name = "ExternalSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.externalSessions == Theme.externalSessions && Theme.externalSessions)
        #expect(settings.setValue("off", forKey: AppSettings.Key.externalSessions))
        #expect(!AppSettings(defaults: defaults).externalSessions, "stored")
        #expect(AppSettings(defaults: defaults, overrides: .init(externalSessions: true)).externalSessions, "a launch argument wins")
    }

    @Test func launchArguments() {
        let arguments = LaunchArguments(["app", "--external-sessions-folder", "/tmp/ext", "--external-sessions", "off"])
        #expect(arguments.externalSessionsFolder?.path == "/tmp/ext")
        #expect(arguments.externalSessions == false)
        #expect(arguments.settingsOverrides.externalSessions == false)
        #expect(LaunchArguments(["app"]).externalSessions == nil)
        #expect(SessionStore.defaultExternalFolder.path.hasSuffix("Library/Application Support/Wallflower/sessions"))
    }
}

/// `scripts/wallflower-session` end to end: it writes, the app's scanner reads.
@Suite("External sessions: helper script")
struct ExternalSessionScriptTests {
    private static let script = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts/wallflower-session")

    @discardableResult
    private func run(_ arguments: [String], folder: URL, sessionID: String? = nil) throws -> Int32 {
        let process = Process()
        process.executableURL = Self.script
        process.arguments = arguments
        var environment = ["WALLFLOWER_SESSIONS_DIR": folder.path, "PATH": "/usr/bin:/bin"]
        if let sessionID { environment["WALLFLOWER_SESSION_ID"] = sessionID }
        process.environment = environment
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func startStatusTouchEndRoundTrip() throws {
        let folder = try TestSupport.makeTempFolder().appending(path: "sessions", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let name = "Fix \"the\" parser\tnow \\ later\nsecond line"
        #expect(try run([
            "start", "--id", "codex-1", "--tool", "codex", "--name", name, "--cwd", "/Users/demo/my project",
            "--pid", "\(TestSupport.livePid)", "--status", "busy", "--open-command", "tmux attach -t 'codex 1'",
        ], folder: folder) == 0)
        var record = try #require(ExternalSessionScanner.scan(folder: folder).records.first)
        #expect(record.id == "codex-1" && record.tool == "codex" && record.name == name && record.cwd == "/Users/demo/my project")
        #expect(record.status == .busy && record.pid == TestSupport.livePid)
        #expect(record.open == .command("tmux attach -t 'codex 1'"))
        #expect(record.startedAt != nil && record.updatedAt == record.statusUpdatedAt)

        #expect(try run(["status", "--id", "codex-1", "waiting", "--waiting-for", "permission"], folder: folder) == 0)
        record = try #require(ExternalSessionScanner.scan(folder: folder).records.first)
        #expect(record.status == .waiting && record.waitingKind == .permission)
        #expect(record.name == name && record.open == .command("tmux attach -t 'codex 1'"), "status keeps the other fields")

        #expect(try run(["status", "idle"], folder: folder, sessionID: "codex-1") == 0, "the id from the environment, as a hook sends it")
        record = try #require(ExternalSessionScanner.scan(folder: folder).records.first)
        #expect(record.status == .idle && record.waitingFor == nil)
        #expect(try run(["touch", "--id", "codex-1"], folder: folder) == 0)

        #expect(try run(["start", "--id", "../escape"], folder: folder) == 1, "ids are file names")
        #expect(try run(["status", "busy"], folder: folder) == 1, "no id at all")
        #expect(try run(["status", "--id", "missing", "busy"], folder: folder) == 1)
        #expect(try run(["start", "--id", "x", "--open-url", "a", "--open-app", "b"], folder: folder) == 1)

        #expect(try run(["end", "--id", "codex-1"], folder: folder) == 0)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left.isEmpty, "no session file and no temp file left")
        #expect(try run(["end", "--id", "codex-1"], folder: folder) == 0, "ending twice is fine")
    }
}
