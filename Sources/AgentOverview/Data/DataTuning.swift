import Foundation

/// Tunable constants of the data layer. They live here and not in `Theme.swift`
/// so the data branch and the UI branch never edit the same file.
enum DataTuning {
    /// How long a session counts as "just finished" after a busy to idle transition. The UI holds the
    /// mint colour and the done halo for exactly this long (`Theme.doneHold` is the same value).
    static let justFinishedDuration: TimeInterval = 8
    /// How long an ended session stays in the store so the UI can fade it out.
    static let endedLinger: TimeInterval = 1
    /// Quiet period after a registry event before the folder is re-scanned.
    static let scanDebounce: DispatchTimeInterval = .milliseconds(50)
    /// Entrypoint of sessions in the Claude desktop app (Settings: "Claude app").
    static let desktopEntrypoints: Set<String> = ["claude-desktop"]
    /// Entrypoints of sessions started in a terminal or an editor (Settings: "Terminal & editors").
    static let terminalEntrypoints: Set<String> = ["cli", "sdk-cli", "claude-vscode"]
    /// Entrypoints shown by default: desktop sessions only (decision 13-10-26); Settings can widen it.
    static let defaultEntrypoints: Set<String> = desktopEntrypoints

    // MARK: External sessions

    /// How long an external session file without a `pid` counts as live after its last write
    /// (`updatedAt` or the file's modification date). Documented in `docs/external-sessions.md`.
    static let externalSessionTTL: TimeInterval = 10 * 60
    /// How long after a TTL expiry the watcher rescans, so the record is past it for sure.
    static let expiryRescanSlack: TimeInterval = 1

    /// How late the one-shot midnight timer of the action faces may fire, so the system can batch it
    /// with other wake-ups. It never fires early.
    static let dayChangeTolerance: TimeInterval = 2

    // MARK: Transcript insights

    /// How much of a session transcript is read from its end per insight computation.
    /// The facts live in the last few lines; 256 KB covers a tool result of a large file read.
    static let transcriptTailBytes = 256 * 1024
    /// How much of a subagent transcript is read from its end to decide whether it finished
    /// (the hand-back report plus its tool result are the last two lines).
    static let subagentTailBytes = 64 * 1024
    /// Quiet period after a transcript event before the insight is recomputed.
    static let insightDebounce: DispatchTimeInterval = .milliseconds(150)
    /// `--log-insights`: `NSLog` pid, activity, subagent count and branch on every change,
    /// plus the cost of the first computation. Never logs names, paths or content.
    static let logInsights = CommandLine.arguments.contains("--log-insights")
}
