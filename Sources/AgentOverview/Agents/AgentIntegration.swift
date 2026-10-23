import Foundation
import WallflowerHookCore

/// Where an agent integration stands, as the Agents tab and the welcome show it.
enum ConnectionState: Equatable, Sendable {
    /// No trace of the tool on this Mac (its folder or app).
    case notInstalled
    /// Installed, Wallflower's hooks are not there.
    case available
    /// Every hook is in place with the current command.
    case connected
    /// Some of Wallflower's hooks are there, but not all, or with an older command: Connect repairs it.
    case outdated
    /// Installed as an app, but the folder its hooks live in does not exist yet.
    case needsFirstRun(String)
    /// The person turned hooks off in the tool; Wallflower never turns them back on.
    case hooksDisabled(String)
    /// The file can't be edited safely (comments, not strict JSON, a symlink, another hook source):
    /// the person adds the lines.
    case manual(String)
    case failed(String)

    var isConnected: Bool { self == .connected }
}

/// One file an integration writes, with the bytes it expects to find (the conflict check) and the
/// bytes it leaves. `after == nil` deletes the file.
struct FileChange: Equatable, Sendable {
    var url: URL
    /// The file as read when the plan was made; nil when it did not exist.
    var before: Data?
    var after: Data?
    /// Folders the write creates (deepest last), recorded so a disconnect can remove them when empty.
    var createdDirectories: [URL] = []
    /// Object key paths the edit added (`["hooks"]`, `["hooks", "Stop"]`), removed again when empty.
    var createdKeys: [[String]] = []

    var createsFile: Bool { before == nil && after != nil }
    var deletesFile: Bool { before != nil && after == nil }

    /// The lines the change adds, for the consent sheet's green diff.
    var addedLines: [String] {
        guard let after else { return [] }
        let new = String(decoding: after, as: UTF8.self).components(separatedBy: "\n")
        guard let before else { return new.filter { !$0.isEmpty } }
        return LineDiff.trimmed(LineDiff.added(old: String(decoding: before, as: UTF8.self).components(separatedBy: "\n"), new: new))
    }

    /// The lines the change removes.
    var removedLines: [String] {
        guard let before else { return [] }
        let old = String(decoding: before, as: UTF8.self).components(separatedBy: "\n")
        guard let after else { return old.filter { !$0.isEmpty } }
        return LineDiff.added(old: String(decoding: after, as: UTF8.self).components(separatedBy: "\n"), new: old)
    }
}

/// Everything one Connect or Disconnect writes.
struct ChangePlan: Equatable, Sendable {
    var tool: AgentTool
    var changes: [FileChange]

    var isEmpty: Bool { changes.isEmpty }
}

/// The setup can't be written for the person: these lines go into this file by hand.
struct ManualSetup: Error, Equatable {
    var reason: String
    var file: URL
    var lines: String
}

/// An agent Wallflower can connect. Two kinds: a config edit (insert Wallflower's entries into the
/// tool's own JSON file) and a drop-in (a file of Wallflower's own in a folder the tool reads).
protocol AgentIntegration: Sendable {
    var tool: AgentTool { get }
    /// Installed: the tool's folder or app exists. Existence only, nothing is read.
    func isInstalled(in environment: AgentEnvironment) -> Bool
    /// Reads the tool's config (only once the person looks at the Agents tab or picked the tool).
    func state(in environment: AgentEnvironment) -> ConnectionState
    /// What Connect writes. Empty when already connected; throws `ManualSetup` when it can't write.
    func connectPlan(in environment: AgentEnvironment) throws -> ChangePlan
    /// What Disconnect writes: only Wallflower's entries go, only files Wallflower created are deleted.
    func disconnectPlan(in environment: AgentEnvironment, record: IntegrationManifest.ToolRecord?) throws -> ChangePlan
    /// The file the row's "Reveal file" shows.
    func primaryFile(in environment: AgentEnvironment) -> URL
}

/// A tiny line diff (longest common subsequence) for the consent sheet. Config files are small.
enum LineDiff {
    /// Without the bare brackets at either end: an existing `}` that only gained a comma reads as
    /// noise in the sheet, the lines in between are what Wallflower adds.
    static func trimmed(_ lines: [String]) -> [String] {
        let bare: (String) -> Bool = { line in line.trimmingCharacters(in: .whitespaces).allSatisfy { "{}[],".contains($0) } }
        var slice = lines[...]
        while let first = slice.first, bare(first), slice.count > 1 { slice = slice.dropFirst() }
        while let last = slice.last, bare(last), slice.count > 1 { slice = slice.dropLast() }
        return Array(slice)
    }

    /// The lines of `new` that are not part of the common subsequence with `old`.
    static func added(old: [String], new: [String]) -> [String] {
        let n = old.count, m = new.count
        guard n * m <= 4_000_000 else { return new.filter { !old.contains($0) } }
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [String] = []
        var i = 0, j = 0
        while j < m {
            if i < n, old[i] == new[j] {
                i += 1
                j += 1
            } else if i < n, table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                if !new[j].isEmpty { result.append(new[j]) }
                j += 1
            }
        }
        return result
    }
}

/// Whether a hook command is one of Wallflower's.
enum WallflowerCommand {
    static func isOurs(_ text: String) -> Bool {
        text.contains(HelperLayout.helperName)
    }
}
