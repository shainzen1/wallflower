import Foundation

/// Facts about a session that come from its transcript rather than the registry.
/// Produced by the transcript reader, applied to `Session` on the main actor.
struct SessionInsight: Equatable, Sendable {
    /// Current activity while working.
    var activity: SessionActivity = .thinking
    /// Number of subagents currently running for this session.
    var subagentCount = 0
    /// Git branch of the working directory, when known.
    var gitBranch: String?
    /// The last tool call in the transcript ended in an error.
    var lastToolFailed = false
}
