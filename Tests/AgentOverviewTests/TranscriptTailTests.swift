import Foundation
import Testing
@testable import AgentOverview

@Suite("TranscriptTail")
struct TranscriptTailTests {
    private func facts(_ fixture: String, startsMidFile: Bool = false) throws -> TranscriptFacts {
        TranscriptTail.facts(from: try TestSupport.transcriptFixtureData(fixture), startsMidFile: startsMidFile)
    }

    @Test func editInFlightIsCoding() throws {
        let facts = try facts("coding")
        #expect(facts.lastToolName == "Edit")
        #expect(facts.lastToolInFlight)
        #expect(facts.inFlightToolUseIds == ["toolu_0001"])
        #expect(!facts.lastResultFailed)
        #expect(facts.gitBranch == "feature/demo")
        #expect(facts.activity(liveSubagents: 0) == .coding)
    }

    @Test func bashInFlightIsRunningAndTrailingNonMessageLinesAreSkipped() throws {
        let facts = try facts("running")
        #expect(facts.lastToolName == "Bash")
        #expect(facts.lastToolInFlight)
        #expect(facts.activity(liveSubagents: 0) == .running)
        #expect(facts.gitBranch == "main")
    }

    @Test func grepInFlightIsReading() throws {
        let facts = try facts("reading")
        #expect(facts.lastToolName == "Grep")
        #expect(facts.activity(liveSubagents: 0) == .reading)
    }

    @Test func parallelAgentCallsWithOneResultLeftIsDelegating() throws {
        let facts = try facts("delegating")
        #expect(facts.lastToolName == "Agent")
        #expect(facts.lastToolInFlight)
        #expect(facts.inFlightToolUseIds == ["toolu_0003"], "the first call already has its result")
        #expect(facts.activity(liveSubagents: 0) == .delegating)
        #expect(!facts.lastResultFailed)
    }

    @Test func finalTextAfterFinishedToolIsThinking() throws {
        let facts = try facts("thinking")
        #expect(facts.lastToolName == nil, "the last message is text only")
        #expect(!facts.lastToolInFlight)
        #expect(facts.inFlightToolUseIds.isEmpty)
        #expect(facts.activity(liveSubagents: 0) == .thinking)
        #expect(!facts.lastResultFailed)
        #expect(facts.gitBranch == "main")
    }

    @Test func finishedToolCallIsThinkingUnlessSubagentsAreLive() throws {
        var data = try TestSupport.transcriptFixtureData("coding")
        data.append(Data((TranscriptLineBuilder.toolResult(id: "toolu_0001") + "\n").utf8))
        let facts = TranscriptTail.facts(from: data, startsMidFile: false)
        #expect(facts.lastToolName == "Edit")
        #expect(!facts.lastToolInFlight)
        #expect(facts.activity(liveSubagents: 0) == .thinking)
        #expect(facts.activity(liveSubagents: 2) == .delegating)
    }

    @Test func errorResultSetsTheFlagWhileTheModelThinks() throws {
        let facts = try facts("error")
        #expect(facts.lastResultFailed)
        #expect(!facts.lastToolInFlight)
        #expect(facts.lastToolName == nil)
        #expect(facts.activity(liveSubagents: 0) == .thinking)
    }

    @Test func partialFirstLineIsDroppedAndEmptyBranchIsNil() throws {
        let facts = try facts("partial-first-line", startsMidFile: true)
        #expect(facts.lastToolName == "NotebookEdit")
        #expect(facts.lastToolInFlight)
        #expect(facts.activity(liveSubagents: 0) == .coding)
        #expect(facts.gitBranch == nil, "the broken first line must not leak its branch")
        #expect(!facts.lastResultFailed)
    }

    @Test func wholeFileIsNotTreatedAsPartial() throws {
        // Read whole: the first (broken) line is parsed and fails, nothing else changes.
        let facts = try facts("partial-first-line", startsMidFile: false)
        #expect(facts.lastToolName == "NotebookEdit")
        #expect(facts.gitBranch == nil)
    }

    @Test func unparseableTrailingLineIsSkipped() throws {
        var data = try TestSupport.transcriptFixtureData("coding")
        data.append(Data("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_res".utf8))
        let facts = TranscriptTail.facts(from: data, startsMidFile: false)
        #expect(facts.lastToolName == "Edit")
        #expect(facts.lastToolInFlight)
    }

    @Test func emptyDataGivesDefaults() {
        let facts = TranscriptTail.facts(from: Data(), startsMidFile: false)
        #expect(facts == TranscriptFacts())
        #expect(facts.activity(liveSubagents: 0) == .thinking)
    }

    @Test func scanStopsEarly() throws {
        // 10 lines; from the end: system (branch), text (group), five bookkeeping lines (skipped
        // without parsing), then the tool result settles the group and the error flag: 8 examined.
        let facts = try facts("thinking")
        #expect(facts.scannedLines == 8, "the opening prompt and the tool call are never examined")
    }

    @Test func tailReadOfAFileBiggerThanTheWindow() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "big.jsonl")
        let padding = String(repeating: TranscriptLineBuilder.attachment(gitBranch: "old-branch") + "\n", count: 400)
        try Data(padding.utf8).write(to: url)
        try TranscriptLineBuilder.append([
            TranscriptLineBuilder.assistantToolUse(id: "toolu_9", name: "Bash", messageId: "msg_9", gitBranch: "new-branch"),
        ], to: url)
        let size = try #require(FileStamp(path: url.path)?.size)
        let window = 16 * 1024
        #expect(size > window)

        let tail = try TranscriptTail.read(url: url, maxBytes: window)
        #expect(tail.startsMidFile)
        #expect(tail.data.count == window)
        let facts = TranscriptTail.facts(from: tail.data, startsMidFile: true)
        #expect(facts.lastToolName == "Bash")
        #expect(facts.lastToolInFlight)
        #expect(facts.gitBranch == "new-branch")

        let whole = try TranscriptTail.read(url: url, maxBytes: size + 1)
        #expect(!whole.startsMidFile)
        #expect(whole.data.count == size)
    }

    @Test func toolActivityMapping() {
        for name in ["Edit", "Write", "MultiEdit", "NotebookEdit"] { #expect(ToolActivityMap.activity(forTool: name) == .coding) }
        #expect(ToolActivityMap.activity(forTool: "Bash") == .running)
        for name in ["Read", "Grep", "Glob", "WebSearch", "WebFetch", "ToolSearch", "mcp__figma__get_screenshot"] {
            #expect(ToolActivityMap.activity(forTool: name) == .reading)
        }
        for name in ["Agent", "Task", "Workflow"] { #expect(ToolActivityMap.activity(forTool: name) == .delegating) }
        for name in ["AskUserQuestion", "SendMessage", "Skill", "SubagentHandback", "Unknown"] {
            #expect(ToolActivityMap.activity(forTool: name) == .thinking)
        }
    }
}
