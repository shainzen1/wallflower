/// Maps the name of the tool call in flight to a `SessionActivity`.
///
/// Names verified in live transcripts on 13-10-26: Bash, Read, Edit, Write, Agent, Skill, ToolSearch,
/// SendMessage, AskUserQuestion, SendUserFile, SubagentHandback, WebSearch and many `mcp__<server>__<tool>`
/// calls. MultiEdit, NotebookEdit, Grep, Glob, WebFetch, Task and Workflow were not seen (sessions run
/// in auto mode use Bash for searching) but are mapped by their documented meaning.
enum ToolActivityMap {
    static let coding: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    static let running: Set<String> = ["Bash"]
    static let reading: Set<String> = ["Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch", "ToolSearch"]
    static let delegating: Set<String> = ["Agent", "Task", "Workflow"]

    /// `mcp__*` tools cannot be told apart by name (a Figma write and a Jira read look alike),
    /// so they all count as reading; the Claude side waits for a server either way.
    static func activity(forTool name: String) -> SessionActivity {
        if coding.contains(name) { return .coding }
        if running.contains(name) { return .running }
        if reading.contains(name) || name.hasPrefix("mcp__") { return .reading }
        if delegating.contains(name) { return .delegating }
        return .thinking
    }
}
