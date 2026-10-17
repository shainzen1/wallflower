import Foundation
import Testing
@testable import AgentOverview

@Suite("TranscriptLocator")
struct TranscriptLocatorTests {
    let locator = TranscriptLocator(projectsFolder: URL(filePath: "/Users/demo/.claude/projects", directoryHint: .isDirectory))

    @Test func slugReplacesEveryNonAlphanumericCharacter() {
        #expect(TranscriptLocator.projectSlug(for: "/Users/demo") == "-Users-demo")
        #expect(TranscriptLocator.projectSlug(for: "/Users/demo/.claude/work_tree 1") == "-Users-demo--claude-work-tree-1")
        #expect(TranscriptLocator.projectSlug(for: "/tmp/-Users-demo/x") == "-tmp--Users-demo-x")
        #expect(TranscriptLocator.projectSlug(for: "/Users/démo") == "-Users-d-mo")
        #expect(TranscriptLocator.projectSlug(for: "") == "")
    }

    @Test func transcriptAndSubagentPaths() {
        let id = "2a5d4578-0000-4000-8000-000000000000"
        #expect(
            locator.transcriptURL(cwd: "/Users/demo/project", sessionId: id).path
                == "/Users/demo/.claude/projects/-Users-demo-project/\(id).jsonl"
        )
        #expect(
            locator.subagentsFolder(cwd: "/Users/demo/project", sessionId: id).path
                == "/Users/demo/.claude/projects/-Users-demo-project/\(id)/subagents"
        )
        #expect(locator.sessionFolder(cwd: "/Users/demo/project", sessionId: id).hasDirectoryPath)
    }

    @Test func recordResolvesThroughItsCurrentSessionId() throws {
        let record = try TestSupport.fixtureRecord("busy-desktop")
        let url = locator.transcriptURL(cwd: record.cwd, sessionId: record.sessionId)
        #expect(url.lastPathComponent == "\(record.sessionId).jsonl")
        #expect(url.deletingLastPathComponent().lastPathComponent == TranscriptLocator.projectSlug(for: record.cwd))
    }

    @Test func defaultFolderIsUnderHome() {
        #expect(TranscriptLocator.defaultProjectsFolder.path.hasSuffix("/.claude/projects"))
    }
}
