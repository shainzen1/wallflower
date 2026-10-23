import AppKit
import WallflowerHookCore

/// The home folder the agent integrations look at and write into, and where Wallflower keeps its own
/// side of them. Every installer works through one of these, never through the process's real home:
/// tests and `--tools-home <dir>` hand in a fixture folder, and nothing can reach the real home there.
struct AgentEnvironment: Sendable {
    /// The home whose tool folders (`.codex`, `.gemini`, ...) are detected and edited.
    let home: URL
    /// Wallflower's own folder: backups, the manifest of what was written, the sessions folder.
    let supportFolder: URL
    /// The folders apps are looked for in, for tools that are apps (Cursor, ChatGPT, Windsurf).
    let applicationFolders: [URL]
    /// Looks an app up by bundle id. The real one asks Launch Services; a fixture home only its own
    /// `Applications` folder, so a check never depends on what this Mac has installed.
    let appLookup: @Sendable (_ bundleIDs: [String], _ names: [String]) -> Bool
    /// True for `--tools-home` and tests: the trust check only looks for a `codex` inside `home`.
    let isFixture: Bool

    /// The real home, Launch Services and `/Applications`.
    static var live: AgentEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = [URL(filePath: "/Applications", directoryHint: .isDirectory), home.appending(path: "Applications", directoryHint: .isDirectory)]
        return AgentEnvironment(home: home, supportFolder: AppInfo.supportFolder, applicationFolders: folders, isFixture: false) { bundleIDs, names in
            let found = bundleIDs.contains { id in
                MainActor.assumeIsolated { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
            }
            return found || names.contains { name in folders.contains { FileManager.default.fileExists(atPath: $0.appending(path: "\(name).app").path) } }
        }
    }

    /// A fixture home: its own `Library/Application Support/Wallflower` and `Applications`, nothing else.
    static func fixture(home: URL) -> AgentEnvironment {
        let applications = home.appending(path: "Applications", directoryHint: .isDirectory)
        return AgentEnvironment(
            home: home, supportFolder: HelperLayout.supportFolder(home: home), applicationFolders: [applications], isFixture: true
        ) { _, names in
            names.contains { FileManager.default.fileExists(atPath: applications.appending(path: "\($0).app").path) }
        }
    }

    init(
        home: URL, supportFolder: URL, applicationFolders: [URL], isFixture: Bool,
        appLookup: @escaping @Sendable ([String], [String]) -> Bool
    ) {
        self.home = home
        self.supportFolder = supportFolder
        self.applicationFolders = applicationFolders
        self.isFixture = isFixture
        self.appLookup = appLookup
    }

    /// `~/.local/share/wallflower/bin/wallflower-hook`: what every hook command runs.
    var helperURL: URL { HelperLayout.helperURL(home: home) }
    /// The sessions folder the helper writes into (and Wallflower reads).
    var sessionsFolder: URL { supportFolder.appending(path: "sessions", directoryHint: .isDirectory) }
    var backupsFolder: URL { supportFolder.appending(path: "backups", directoryHint: .isDirectory) }
    var manifestURL: URL { supportFolder.appending(path: "integrations.json", directoryHint: .notDirectory) }

    /// A path below the home folder.
    func path(_ relative: String) -> URL {
        home.appending(path: relative)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative).path)
    }

    /// The hook command for one event: the helper, the tool and the event. The helper's path has no
    /// spaces in a normal home, so the command needs no quotes; a home with a space gets them.
    func command(tool: AgentTool, event: String) -> String {
        "\(ShellQuote.quote(helperURL.path)) \(tool.rawValue) \(event)"
    }
}

/// POSIX shell quoting that leaves a plain path alone.
enum ShellQuote {
    static func quote(_ text: String) -> String {
        let plain = text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "/._-+@%:,".unicodeScalars.contains($0) }
        if plain, !text.isEmpty { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
