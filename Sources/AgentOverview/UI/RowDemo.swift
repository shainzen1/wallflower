import Foundation

/// `--demo-states`: a temporary override for judging the visual states on the real registry.
/// While enabled, `PanelModel` shows the first row as working and delegating with three subagent
/// satellites, the second as working and coding, both with a branch, whatever the sessions do.
/// Off unless the argument is present.
@MainActor
enum RowDemo {
    static var enabled = CommandLine.arguments.contains("--demo-states")
    /// Row 0 and row 1: activity and satellites.
    nonisolated static let activity: SessionActivity = .delegating
    nonisolated static let subagentCount = 3
    nonisolated static let secondActivity: SessionActivity = .coding
    nonisolated static let secondSubagentCount = 0
    nonisolated static let gitBranch = "main"
    /// Project keys of the two demo rows, so `.project` colour mode shows two hues next to the real ones
    /// (these two hash to different palette colours; `web` and `api` would share one).
    nonisolated static let projectKey = "web-app"
    nonisolated static let secondProjectKey = "api"
}
