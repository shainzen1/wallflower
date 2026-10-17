import Foundation
import Testing
@testable import AgentOverview

@Suite("Detached HEAD is no branch")
struct GitBranchNameTests {
    @Test func normalisation() {
        #expect(GitBranchName.normalized("main") == "main")
        #expect(GitBranchName.normalized(" feature/x \n") == "feature/x")
        #expect(GitBranchName.normalized("HEAD") == nil)
        #expect(GitBranchName.normalized("") == nil)
        #expect(GitBranchName.normalized("   ") == nil)
        #expect(GitBranchName.normalized(nil) == nil)
        #expect(GitBranchName.normalized("head") == "head", "only the literal detached marker is hidden")
    }

    @Test func gitHeadReaderHidesHead() {
        #expect(GitHeadReader.branch(headContents: "ref: refs/heads/HEAD\n") == nil)
        #expect(GitHeadReader.branch(headContents: "ref: refs/heads/main\n") == "main")
        #expect(GitHeadReader.branch(headContents: "0123456789abcdef0123456789abcdef01234567\n") == nil)
    }

    @Test func transcriptTailSkipsHeadAndKeepsLooking() throws {
        let lines = [
            TranscriptLineBuilder.attachment(gitBranch: "real-branch"),
            TranscriptLineBuilder.assistantText(messageId: "msg_1", gitBranch: "HEAD"),
        ]
        let data = Data(lines.joined(separator: "\n").utf8)
        let facts = TranscriptTail.facts(from: data, startsMidFile: false)
        #expect(facts.gitBranch == "real-branch", "the newest line says HEAD; the older line names the branch")

        let onlyHead = Data(TranscriptLineBuilder.assistantText(messageId: "msg_1", gitBranch: "HEAD").utf8)
        #expect(TranscriptTail.facts(from: onlyHead, startsMidFile: false).gitBranch == nil)
    }
}
