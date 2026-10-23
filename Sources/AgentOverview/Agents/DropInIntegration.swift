import Foundation
import WallflowerHookCore

/// A drop-in integration: files of Wallflower's own in a folder the tool reads by itself. Connect
/// writes them, Disconnect deletes them; no file of the person's is ever opened for writing. Used for
/// Copilot (`~/.copilot/hooks/wallflower.json`), OpenCode (`~/.config/opencode/plugins/wallflower.js`)
/// and Goose (`~/.agents/plugins/wallflower/`).
struct DropInIntegration: AgentIntegration {
    let tool: AgentTool
    /// The tool's folder: Connect needs it to exist.
    let toolFolder: String
    let detectPaths: [String]
    let appBundleIDs: [String]
    let appNames: [String]
    /// The files, relative to the home folder, with their content for an environment.
    let files: @Sendable (AgentEnvironment) -> [(path: String, content: Data)]

    init(
        tool: AgentTool, toolFolder: String, detectPaths: [String]? = nil, appBundleIDs: [String] = [], appNames: [String] = [],
        files: @escaping @Sendable (AgentEnvironment) -> [(path: String, content: Data)]
    ) {
        self.tool = tool
        self.toolFolder = toolFolder
        self.detectPaths = detectPaths ?? [toolFolder]
        self.appBundleIDs = appBundleIDs
        self.appNames = appNames
        self.files = files
    }

    func primaryFile(in environment: AgentEnvironment) -> URL {
        environment.path(files(environment).first?.path ?? toolFolder)
    }

    func isInstalled(in environment: AgentEnvironment) -> Bool {
        detectPaths.contains(where: environment.exists) || (!appNames.isEmpty && environment.appLookup(appBundleIDs, appNames))
    }

    func state(in environment: AgentEnvironment) -> ConnectionState {
        guard isInstalled(in: environment) else { return .notInstalled }
        guard environment.exists(toolFolder) else { return .needsFirstRun("Open \(tool.displayName) once, then connect.") }
        let present = files(environment).map { IntegrationStore.read(environment.path($0.path)) == $0.content }
        if present.allSatisfy({ $0 }) { return .connected }
        let anyOurs = files(environment).contains { environment.exists($0.path) }
        return anyOurs ? .outdated : .available
    }

    func connectPlan(in environment: AgentEnvironment) throws -> ChangePlan {
        let files = files(environment)
        guard environment.exists(toolFolder) else {
            throw ManualSetup(reason: "Open \(tool.displayName) once, then connect.", file: environment.path(toolFolder), lines: "")
        }
        var changes: [FileChange] = []
        for file in files {
            let url = environment.path(file.path)
            let before = IntegrationStore.read(url)
            guard before != file.content else { continue }
            if before != nil, IntegrationStore.isSymlink(url) {
                throw ManualSetup(reason: "\(url.lastPathComponent) is a link to another file, so Wallflower won't replace it.", file: url, lines: "")
            }
            changes.append(FileChange(url: url, before: before, after: file.content, createdDirectories: missingFolders(above: url, in: environment)))
        }
        return ChangePlan(tool: tool, changes: changes)
    }

    func disconnectPlan(in environment: AgentEnvironment, record: IntegrationManifest.ToolRecord?) throws -> ChangePlan {
        // Only Wallflower's own files, and each only when it is still recognisably Wallflower's (its
        // current content, or a record that Wallflower created it).
        let changes = files(environment).compactMap { file -> FileChange? in
            let url = environment.path(file.path)
            guard let before = IntegrationStore.read(url) else { return nil }
            guard before == file.content || record?.file(url)?.createdFile == true
                || String(decoding: before, as: UTF8.self).contains(HelperLayout.helperName) || before.range(of: Self.marker) != nil else { return nil }
            return FileChange(url: url, before: before, after: nil)
        }
        return ChangePlan(tool: tool, changes: changes)
    }

    /// Every drop-in file Wallflower writes carries this marker.
    static let marker = Data("wallflower".utf8)

    /// The folders above `url` (below the home folder) that do not exist yet, outermost first.
    private func missingFolders(above url: URL, in environment: AgentEnvironment) -> [URL] {
        var folders: [URL] = []
        var folder = url.deletingLastPathComponent()
        let home = environment.home.standardizedFileURL.path
        while folder.standardizedFileURL.path.count > home.count, !FileManager.default.fileExists(atPath: folder.path) {
            folders.insert(folder, at: 0)
            folder = folder.deletingLastPathComponent()
        }
        return folders
    }
}
