import Foundation
import Testing
@testable import AgentOverview

@Suite("SubagentScanner")
struct SubagentScannerTests {
    private let tailBytes = DataTuning.subagentTailBytes

    @Test func fixtureFolderHasOneLiveAndOneFinished() {
        var cache: [String: SubagentScanner.Verdict] = [:]
        let live = SubagentScanner.liveCount(in: TestSupport.subagentsFixtureFolder, tailBytes: tailBytes, cache: &cache)
        #expect(live == 1)
        #expect(cache["a1111111111111111"]?.finished == true, "ends with SubagentHandback and its result")
        #expect(cache["a2222222222222222"]?.finished == false, "ends with a Bash call in flight")
    }

    @Test func handbackRuleOnTails() throws {
        let finished = try Data(contentsOf: TestSupport.subagentsFixtureFolder.appending(path: "agent-a1111111111111111.jsonl"))
        #expect(SubagentScanner.isFinished(tail: finished, startsMidFile: false))
        let live = try Data(contentsOf: TestSupport.subagentsFixtureFolder.appending(path: "agent-a2222222222222222.jsonl"))
        #expect(!SubagentScanner.isFinished(tail: live, startsMidFile: false))

        // A continued agent: a new prompt after the hand-back makes it live again.
        var continued = finished
        continued.append(Data((TranscriptLineBuilder.toolResult(id: "toolu_0999") + "\n").utf8))
        #expect(!SubagentScanner.isFinished(tail: continued, startsMidFile: false))

        // A plain tool result at the end (no hand-back) is not completion.
        #expect(!SubagentScanner.isFinished(tail: Data(), startsMidFile: false))
    }

    @Test func prefixFileMarksCompletionAndCacheFollowsChanges() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let liveSource = TestSupport.subagentsFixtureFolder.appending(path: "agent-a2222222222222222.jsonl")
        let one = folder.appending(path: "agent-b1.jsonl")
        let two = folder.appending(path: "agent-b2.jsonl")
        try FileManager.default.copyItem(at: liveSource, to: one)
        try FileManager.default.copyItem(at: liveSource, to: two)
        try Data("{}".utf8).write(to: folder.appending(path: "agent-b2.meta.json"))

        var cache: [String: SubagentScanner.Verdict] = [:]
        #expect(SubagentScanner.liveCount(in: folder, tailBytes: tailBytes, cache: &cache) == 2)

        // The prefix file written at completion finishes b2 without reading its tail.
        try Data("{\"v\":1}".utf8).write(to: folder.appending(path: "agent-b2.prefix.json"))
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: two.path)
        #expect(SubagentScanner.liveCount(in: folder, tailBytes: tailBytes, cache: &cache) == 1)

        // b1 hands back: its stamp changes, the verdict is recomputed.
        try TranscriptLineBuilder.append([
            TranscriptLineBuilder.assistantToolUse(id: "toolu_0777", name: "SubagentHandback", messageId: "msg_7"),
            TranscriptLineBuilder.toolResult(id: "toolu_0777"),
        ], to: one)
        #expect(SubagentScanner.liveCount(in: folder, tailBytes: tailBytes, cache: &cache) == 0)
        #expect(cache.count == 2)

        // A removed file drops out of the cache; a missing folder counts zero.
        try FileManager.default.removeItem(at: two)
        #expect(SubagentScanner.liveCount(in: folder, tailBytes: tailBytes, cache: &cache) == 0)
        #expect(cache.keys.sorted() == ["b1"])
        #expect(SubagentScanner.liveCount(in: folder.appending(path: "missing"), tailBytes: tailBytes, cache: &cache) == 0)
        #expect(cache.isEmpty)
    }
}
