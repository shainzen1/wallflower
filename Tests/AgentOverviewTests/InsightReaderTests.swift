import Foundation
import Testing
@testable import AgentOverview

/// End to end: temp registry, temp projects folder, temp cwd. Lines are appended to the transcript
/// like Claude Code does and the insight must follow within a second. Only the test polls.
@Suite("InsightReader end to end", .serialized)
@MainActor
struct InsightReaderTests {
    @Test func insightFollowsTranscriptSubagentsAndSessionIdRotation() async throws {
        let root = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appending(path: "sessions", directoryHint: .isDirectory)
        let projects = root.appending(path: "projects", directoryHint: .isDirectory)
        let cwd = root.appending(path: "work", directoryHint: .isDirectory)
        let git = cwd.appending(path: ".git", directoryHint: .isDirectory)
        for folder in [registry, projects, git] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("ref: refs/heads/head-branch\n".utf8).write(to: git.appending(path: "HEAD"))

        let locator = TranscriptLocator(projectsFolder: projects)
        let sessionA = "aaaaaaaa-0000-4000-8000-000000000001"
        let transcriptA = locator.transcriptURL(cwd: cwd.path, sessionId: sessionA)
        try FileManager.default.createDirectory(at: transcriptA.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TranscriptLineBuilder.append([
            TranscriptLineBuilder.assistantToolUse(id: "toolu_1", name: "Bash", messageId: "msg_1", gitBranch: nil),
        ], to: transcriptA)

        let store = SessionStore(folder: registry, projectsFolder: projects)
        defer { store.stop() }
        store.start()
        #expect(await TestSupport.waitUntil { store.hasScanned })

        // The session appears: initial read, branch from .git/HEAD because the lines carry none.
        let pid = TestSupport.livePid
        try TestSupport.writeFixture("busy-desktop", to: registry, pid: pid, cwd: cwd.path, sessionId: sessionA)
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.activity == .running })
        #expect(session.gitBranch == "head-branch")
        #expect(session.subagentCount == 0)
        #expect(!session.lastToolFailed)

        // The call fails and the model thinks about it.
        try TranscriptLineBuilder.append([
            TranscriptLineBuilder.toolResult(id: "toolu_1", isError: true, gitBranch: nil),
            TranscriptLineBuilder.assistantText(messageId: "msg_2", gitBranch: nil),
        ], to: transcriptA)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.activity == .thinking && session.lastToolFailed })

        // An edit starts; the transcript now carries a branch, which wins over .git/HEAD.
        try TranscriptLineBuilder.append([
            TranscriptLineBuilder.assistantToolUse(id: "toolu_2", name: "Edit", messageId: "msg_3", gitBranch: "txn-branch"),
        ], to: transcriptA)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.activity == .coding && session.gitBranch == "txn-branch" })
        #expect(session.lastToolFailed, "the error flag stays until the next result")

        // A subagents folder appears with one live and one finished agent.
        let subagents = locator.subagentsFolder(cwd: cwd.path, sessionId: sessionA)
        try FileManager.default.createDirectory(at: subagents.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestSupport.subagentsFixtureFolder, to: subagents)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.subagentCount == 1 })
        #expect(session.activity == .coding, "a tool in flight wins over delegating")

        // The edit finishes: nothing in flight, a live subagent means delegating.
        try TranscriptLineBuilder.append([TranscriptLineBuilder.toolResult(id: "toolu_2", gitBranch: "txn-branch")], to: transcriptA)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.activity == .delegating && !session.lastToolFailed })

        // The session id rotates (resume): the reader follows the registry to the new transcript.
        let sessionB = "bbbbbbbb-0000-4000-8000-000000000002"
        let transcriptB = locator.transcriptURL(cwd: cwd.path, sessionId: sessionB)
        try FileManager.default.copyItem(at: TestSupport.transcriptFixtureURL("coding"), to: transcriptB)
        try TestSupport.writeFixture("busy-desktop", to: registry, pid: pid, cwd: cwd.path, sessionId: sessionB)
        #expect(await TestSupport.waitUntil(timeout: 1) {
            session.activity == .coding && session.gitBranch == "feature/demo" && session.subagentCount == 0
        })
    }

    @Test func transcriptAppearingLaterIsPickedUp() async throws {
        let root = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appending(path: "sessions", directoryHint: .isDirectory)
        let projects = root.appending(path: "projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        let store = SessionStore(folder: registry, projectsFolder: projects)
        defer { store.stop() }
        store.start()
        let pid = TestSupport.livePid
        let sessionId = "cccccccc-0000-4000-8000-000000000003"
        try TestSupport.writeFixture("busy-desktop", to: registry, pid: pid, cwd: "/Users/demo/new", sessionId: sessionId)
        #expect(await TestSupport.waitUntil(timeout: 1) { store.sessions.count == 1 })
        let session = try #require(store.sessions.first)
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.activity == .thinking)
        #expect(session.gitBranch == nil)

        // Neither the project folder nor the transcript existed; both appear now.
        let locator = TranscriptLocator(projectsFolder: projects)
        let transcript = locator.transcriptURL(cwd: "/Users/demo/new", sessionId: sessionId)
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: TestSupport.transcriptFixtureURL("reading"), to: transcript)
        #expect(await TestSupport.waitUntil(timeout: 1) { session.activity == .reading && session.gitBranch == "main" })

        // Ending the session stops its reader: later appends change nothing.
        try FileManager.default.removeItem(at: registry.appending(path: "\(pid).json"))
        #expect(await TestSupport.waitUntil(timeout: 1) { session.ended })
        try TranscriptLineBuilder.append([TranscriptLineBuilder.toolResult(id: "toolu_0002")], to: transcript)
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.activity == .reading)
    }
}
