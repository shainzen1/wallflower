import Foundation
import Testing
@testable import AgentOverview

/// End-to-end against a temp folder with the real `DispatchSource` watcher.
/// The tests poll with `Task.sleep`; the store itself never does.
@Suite("SessionStore end to end", .serialized)
@MainActor
struct SessionStoreTests {
    @Test func appearsChangesSortsAndEnds() async throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SessionStore(folder: folder)
        defer { store.stop() }
        store.start()
        #expect(await TestSupport.waitUntil { store.hasScanned })
        #expect(store.sessions.isEmpty)

        // A busy session appears.
        let pid = TestSupport.livePid
        let file = try TestSupport.writeFixture("busy-desktop", to: folder, pid: pid, statusUpdatedAt: 1_000_000)
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        #expect(session.pid == pid)
        #expect(session.state == .working)
        #expect(session.name == "Refactor billing hooks")
        #expect(session.hostSessionId != nil)

        // Same file rewritten in place as idle: busy to idle is "just finished".
        try TestSupport.writeFixture("busy-desktop", to: folder, pid: pid, status: .idle, statusUpdatedAt: 2_000_000)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.state == .idle })
        #expect(session.justFinishedUntil != nil)
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first === session)

        // A second, idle session with a more recent state change sorts above the first one.
        let pid2 = TestSupport.livePid + 50_000  // dead pid: must be filtered out as stale
        try TestSupport.writeFixture("idle-desktop", to: folder, pid: pid2, statusUpdatedAt: 3_000_000)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.sessions.count == 1, "a file whose pid is dead must not become a session")

        // Now a live second session: spawn a helper process so its pid is alive and distinct.
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sleep")
        helper.arguments = ["30"]
        try helper.run()
        defer { helper.terminate() }
        try FileManager.default.removeItem(at: folder.appending(path: "\(pid2).json"))
        try TestSupport.writeFixture("idle-desktop", to: folder, pid: helper.processIdentifier, statusUpdatedAt: 3_000_000)
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 2 })
        #expect(store.sessions.map(\.pid) == [helper.processIdentifier, pid])

        // The first session starts waiting on a question: it sorts first although its change is older.
        try TestSupport.writeFixture(
            "busy-desktop", to: folder, pid: pid, status: .waiting, waitingFor: "input needed", statusUpdatedAt: 2_500_000
        )
        #expect(await TestSupport.waitUntil(timeout: 1) { session.state == .needsInput(kind: .question) })
        #expect(store.sessions.map(\.pid) == [pid, helper.processIdentifier])
        #expect(session.justFinishedUntil == nil)

        // Deleting the file ends the session, which is removed after the linger.
        try FileManager.default.removeItem(at: file)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.ended })
        #expect(store.sessions.contains { $0 === session }, "ended sessions linger for the fade out")
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 1) { store.sessions.count == 1 })
        #expect(store.sessions.first?.pid == helper.processIdentifier)
    }

    @Test func processExitEndsSessionWithoutDeletingFile() async throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sleep")
        helper.arguments = ["0.5"]
        try helper.run()
        let pid = helper.processIdentifier
        let file = try TestSupport.writeFixture("busy-desktop", to: folder, pid: pid)

        let store = SessionStore(folder: folder)
        defer { store.stop() }
        store.start()
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        #expect(session.pid == pid)
        #expect(!session.ended)

        #expect(await TestSupport.waitUntil(timeout: 2) { session.ended })
        #expect(FileManager.default.fileExists(atPath: file.path), "the file is untouched; the kernel reported the exit")
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 1) { store.sessions.isEmpty })
        helper.waitUntilExit()
    }

    @Test func initialScanReportsCountAndFiltersEntrypoint() async throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestSupport.writeFixture("busy-cli", to: folder, pid: TestSupport.livePid)

        let desktopOnly = SessionStore(folder: folder)
        defer { desktopOnly.stop() }
        var reported: Int?
        desktopOnly.onFirstScan = { reported = $0 }
        desktopOnly.start()
        #expect(await TestSupport.waitUntil { desktopOnly.hasScanned })
        #expect(reported == 0)
        #expect(desktopOnly.sessions.isEmpty)

        let all = SessionStore(folder: folder, entrypoints: nil)
        defer { all.stop() }
        all.start()
        #expect(await TestSupport.waitUntil { all.hasScanned })
        #expect(all.sessions.count == 1)
        #expect(all.sessions.first?.entrypoint == "sdk-cli")
        #expect(all.sessions.first?.hostSessionId == nil)
    }

    @Test("No ~/.claude at all: the watcher follows the folders down level by level as they appear")
    func missingAncestorsAreFollowedDown() async throws {
        let home = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = home.appending(path: ".claude", directoryHint: .isDirectory)
        let folder = claude.appending(path: "sessions", directoryHint: .isDirectory)
        let store = SessionStore(folder: folder, projectsFolder: home)
        defer { store.stop() }
        store.start()
        #expect(await TestSupport.waitUntil { store.hasScanned })
        #expect(store.sessions.isEmpty)

        // One level at a time, with a pause so the watcher re-arms on each.
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: false)
        try await Task.sleep(for: .milliseconds(200))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try await Task.sleep(for: .milliseconds(200))
        try TestSupport.writeFixture("busy-desktop", to: folder, pid: TestSupport.livePid)
        #expect(await TestSupport.waitUntil { store.sessions.count == 1 })

        // Gone again and recreated in one go (`mkdir -p`).
        try FileManager.default.removeItem(at: claude)
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 2) { store.sessions.isEmpty })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TestSupport.writeFixture("idle-desktop", to: folder, pid: TestSupport.livePid)
        #expect(await TestSupport.waitUntil { store.sessions.first?.state == .idle })
    }
}
