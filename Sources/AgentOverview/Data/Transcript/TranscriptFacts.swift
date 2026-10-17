import Foundation

/// What the tail of a session transcript says. Pure data; produced by `TranscriptTail.facts(from:)`.
struct TranscriptFacts: Equatable, Sendable {
    /// Name of the tool call that matters: the one in flight if any, else the last one of the
    /// last assistant message. `nil` when no tool call was found in the tail.
    var lastToolName: String?
    /// The last assistant message has at least one `tool_use` without a matching `tool_result` yet.
    var lastToolInFlight = false
    /// Ids of the `tool_use` blocks of the last assistant message that have no result yet
    /// (several when the model called tools in parallel).
    var inFlightToolUseIds: Set<String> = []
    /// `is_error: true` on the most recent `tool_result` in the tail.
    var lastResultFailed = false
    /// Top-level `gitBranch` of the most recent line that carries a non-empty one.
    var gitBranch: String?
    /// Lines examined before the scan could stop (diagnostics only).
    var scannedLines = 0

    /// Activity rules (verified 13-10-26):
    /// 1. A `tool_use` in flight is mapped by its name (`ToolActivityMap`).
    /// 2. Otherwise, live subagents mean the session is delegating. Background `Agent` calls get their
    ///    `tool_result` immediately (`async_launched`), so an in-flight `Agent` only covers foreground calls;
    ///    the subagents folder is the real signal.
    /// 3. Otherwise the model is thinking: it streams text, or it is working on the result it just got.
    func activity(liveSubagents: Int) -> SessionActivity {
        if lastToolInFlight, let name = lastToolName { return ToolActivityMap.activity(forTool: name) }
        if liveSubagents > 0 { return .delegating }
        return .thinking
    }
}
