import Foundation
import WallflowerHookCore

/// A config-edit integration: Wallflower's entries go into the tool's own JSON file under
/// `hooks.<event>`, one per event, and nothing else in the file changes (`JSONText` splices them in).
/// Used for Codex (`~/.codex/hooks.json`), Gemini CLI (`~/.gemini/settings.json`), Cursor
/// (`~/.cursor/hooks.json`), Windsurf (`~/.codeium/windsurf/hooks.json`) and Devin CLI
/// (`~/.config/devin/config.json`).
struct HookFileIntegration: AgentIntegration {
    /// How one event's entry looks in the tool's format.
    enum EntryStyle: Sendable {
        /// Claude-style matcher groups: `{"matcher": ..., "hooks": [{"type": "command", "command": ..., "timeout": ...}]}`.
        /// `name` adds a `name` (Gemini), `matcher` a `matcher`, `timeout` returns the value per event.
        case group(name: String?, matcher: String?, timeout: @Sendable (String) -> Int)
        /// A flat list of command objects: `{"command": ..., <extra>}` (Cursor, Windsurf).
        case flat(extra: [(String, JSONLiteral)])
    }

    let tool: AgentTool
    /// The config file, relative to the home folder.
    let configPath: String
    /// The tool's folder: Connect needs it to exist (the tool ran at least once).
    let toolFolder: String
    /// Paths and apps whose existence means the tool is installed.
    let detectPaths: [String]
    let appBundleIDs: [String]
    let appNames: [String]
    let style: EntryStyle
    /// Members a file Wallflower creates starts with, before `hooks` (Cursor's `"version": 1`).
    let newFilePrefix: [(String, JSONLiteral)]
    /// Tool-specific checks on top of the file: hooks turned off, a second hook source.
    let extraState: (@Sendable (AgentEnvironment, JSONText?) -> ConnectionState?)?

    init(
        tool: AgentTool, configPath: String, toolFolder: String, detectPaths: [String]? = nil, appBundleIDs: [String] = [], appNames: [String] = [],
        style: EntryStyle, newFilePrefix: [(String, JSONLiteral)] = [], extraState: (@Sendable (AgentEnvironment, JSONText?) -> ConnectionState?)? = nil
    ) {
        self.tool = tool
        self.configPath = configPath
        self.toolFolder = toolFolder
        self.detectPaths = detectPaths ?? [toolFolder]
        self.appBundleIDs = appBundleIDs
        self.appNames = appNames
        self.style = style
        self.newFilePrefix = newFilePrefix
        self.extraState = extraState
    }

    func primaryFile(in environment: AgentEnvironment) -> URL {
        environment.path(configPath)
    }

    func isInstalled(in environment: AgentEnvironment) -> Bool {
        detectPaths.contains(where: environment.exists) || (!appNames.isEmpty && environment.appLookup(appBundleIDs, appNames))
    }

    func state(in environment: AgentEnvironment) -> ConnectionState {
        guard isInstalled(in: environment) else { return .notInstalled }
        guard environment.exists(toolFolder) else { return .needsFirstRun("Open \(tool.displayName) once, then connect.") }
        let url = primaryFile(in: environment)
        let data = IntegrationStore.read(url)
        let document = data.flatMap { try? JSONText($0) }
        if let extra = extraState?(environment, document) { return extra }
        guard let data else { return .available }
        guard let document else {
            // Not strict JSON: connected only if every command is there by hand.
            let text = String(decoding: data, as: UTF8.self)
            if HookEvents.events(for: tool).allSatisfy({ text.contains(environment.command(tool: tool, event: $0)) }) { return .connected }
            return .manual("\(url.lastPathComponent) has comments or isn't strict JSON, so Wallflower won't edit it.")
        }
        let present = presentCommands(in: document)
        let expected = Set(HookEvents.events(for: tool).map { environment.command(tool: tool, event: $0) })
        if present.isEmpty {
            return IntegrationStore.isSymlink(url) ? .manual("\(url.lastPathComponent) is a link to another file, so Wallflower won't edit it.") : .available
        }
        return present == expected ? .connected : .outdated
    }

    func connectPlan(in environment: AgentEnvironment) throws -> ChangePlan {
        let url = primaryFile(in: environment)
        guard environment.exists(toolFolder) else {
            throw ManualSetup(reason: "Open \(tool.displayName) once, then connect.", file: url, lines: manualLines(environment))
        }
        if let extra = extraState?(environment, nil), case .manual(let reason) = extra {
            throw ManualSetup(reason: reason, file: url, lines: manualLines(environment))
        }
        guard let before = IntegrationStore.read(url) else {
            return ChangePlan(tool: tool, changes: [FileChange(url: url, before: nil, after: newFile(environment), createdKeys: [["hooks"]])])
        }
        if IntegrationStore.isSymlink(url) {
            throw ManualSetup(reason: "\(url.lastPathComponent) is a link to another file, so Wallflower won't edit it.", file: url, lines: manualLines(environment))
        }
        var document: JSONText
        do {
            document = try JSONText(before)
        } catch {
            throw ManualSetup(reason: "\(url.lastPathComponent) has comments or isn't strict JSON, so Wallflower won't edit it.", file: url, lines: manualLines(environment))
        }
        guard document.root.isObject else {
            throw ManualSetup(reason: "\(url.lastPathComponent) doesn't hold a JSON object.", file: url, lines: manualLines(environment))
        }
        var createdKeys: [[String]] = []
        let events = HookEvents.events(for: tool)
        // Old entries first (an older helper path, an event no longer used), then the missing ones.
        document = try removeEntries(from: document) { command in
            !events.contains { command == environment.command(tool: tool, event: $0) }
        }
        let present = presentCommands(in: document)
        let missing = events.filter { !present.contains(environment.command(tool: tool, event: $0)) }
        if !missing.isEmpty {
            if let hooks = document.root["hooks"] {
                guard hooks.isObject else {
                    throw ManualSetup(reason: "\"hooks\" in \(url.lastPathComponent) isn't an object.", file: url, lines: manualLines(environment))
                }
                for event in missing {
                    let hooks = document.root["hooks"]!
                    if let list = hooks[event] {
                        guard list.isArray else {
                            throw ManualSetup(reason: "\"\(event)\" in \(url.lastPathComponent) isn't a list.", file: url, lines: manualLines(environment))
                        }
                        document = try JSONText(bytes: document.appendingElement(to: list, value: entry(event, environment)))
                    } else {
                        document = try JSONText(bytes: document.appendingMember(to: hooks, key: event, value: .array([entry(event, environment)])))
                        createdKeys.append(["hooks", event])
                    }
                }
            } else {
                document = try JSONText(bytes: document.appendingMember(to: document.root, key: "hooks", value: hooksObject(events: missing, environment)))
                createdKeys.append(["hooks"])
            }
        }
        guard document.data != before else { return ChangePlan(tool: tool, changes: []) }
        return ChangePlan(tool: tool, changes: [FileChange(url: url, before: before, after: document.data, createdKeys: createdKeys)])
    }

    func disconnectPlan(in environment: AgentEnvironment, record: IntegrationManifest.ToolRecord?) throws -> ChangePlan {
        let url = primaryFile(in: environment)
        guard let before = IntegrationStore.read(url) else { return ChangePlan(tool: tool, changes: []) }
        let file = record?.file(url)
        // Untouched since Wallflower wrote it: put back exactly what was there (unless that already
        // held a Wallflower hook pasted by hand, which has to go too).
        if let file, IntegrationStore.hash(before) == file.writtenHash {
            if file.createdFile { return ChangePlan(tool: tool, changes: [FileChange(url: url, before: before, after: nil)]) }
            if let backup = file.backup, let original = try? Data(contentsOf: URL(filePath: backup)), IntegrationStore.hash(original) == file.beforeHash,
               !String(decoding: original, as: UTF8.self).contains(HelperLayout.helperName) {
                return ChangePlan(tool: tool, changes: [FileChange(url: url, before: before, after: original)])
            }
        }
        guard var document = try? JSONText(before) else {
            if String(decoding: before, as: UTF8.self).contains(HelperLayout.helperName) {
                throw ManualSetup(reason: "\(url.lastPathComponent) has comments now, so Wallflower won't edit it. Remove the wallflower-hook lines yourself.", file: url, lines: manualLines(environment))
            }
            return ChangePlan(tool: tool, changes: [])
        }
        document = try removeEntries(from: document) { _ in true }
        // Keys Wallflower added that are empty now go too, deepest first.
        for path in (file?.createdKeys ?? []).sorted(by: { $0.count > $1.count }) {
            guard let parent = document.node(at: Array(path.dropLast())), let index = parent.members.firstIndex(where: { $0.key == path.last }) else { continue }
            let node = parent.members[index].node
            guard node.members.isEmpty, node.elements.isEmpty, node.isObject || node.isArray else { continue }
            document = try JSONText(bytes: document.removingMember(of: parent, at: index))
        }
        // A file Wallflower created that holds nothing else any more is deleted.
        if file?.createdFile == true, isEmptySkeleton(document) {
            return ChangePlan(tool: tool, changes: [FileChange(url: url, before: before, after: nil)])
        }
        guard document.data != before else { return ChangePlan(tool: tool, changes: []) }
        return ChangePlan(tool: tool, changes: [FileChange(url: url, before: before, after: document.data)])
    }

    /// The `"hooks"` block a person pastes in when Wallflower can't edit the file.
    func manualLines(_ environment: AgentEnvironment) -> String {
        "\"hooks\": " + hooksObject(events: HookEvents.events(for: tool), environment).render(indent: "", unit: "  ", compact: false)
    }

    // MARK: Private

    private func entry(_ event: String, _ environment: AgentEnvironment) -> JSONLiteral {
        let command = environment.command(tool: tool, event: event)
        switch style {
        case .group(let name, let matcher, let timeout):
            var hook: [(String, JSONLiteral)] = []
            if let name { hook.append(("name", .string(name))) }
            hook += [("type", .string("command")), ("command", .string(command)), ("timeout", .int(timeout(event)))]
            var group: [(String, JSONLiteral)] = []
            if let matcher { group.append(("matcher", .string(matcher))) }
            group.append(("hooks", .array([.object(hook)])))
            return .object(group)
        case .flat(let extra):
            return .object([("command", .string(command))] + extra)
        }
    }

    private func hooksObject(events: [String], _ environment: AgentEnvironment) -> JSONLiteral {
        .object(events.map { ($0, .array([entry($0, environment)])) })
    }

    private func newFile(_ environment: AgentEnvironment) -> Data {
        let root = JSONLiteral.object(newFilePrefix + [("hooks", hooksObject(events: HookEvents.events(for: tool), environment))])
        return Data((root.render(indent: "", unit: "  ", compact: false) + "\n").utf8)
    }

    private func isEmptySkeleton(_ document: JSONText) -> Bool {
        let prefixKeys = Set(newFilePrefix.map(\.0))
        return document.root.members.allSatisfy { member in
            prefixKeys.contains(member.key) || (member.key == "hooks" && member.node.members.isEmpty)
        }
    }

    /// Every Wallflower command under `hooks`.
    private func presentCommands(in document: JSONText) -> Set<String> {
        guard let hooks = document.root["hooks"] else { return [] }
        return Set(hooks.members.flatMap { $0.node.allStrings }.filter(WallflowerCommand.isOurs))
    }

    /// Removes Wallflower's entries whose command `shouldRemove` picks: a group whose hooks are all
    /// Wallflower's goes as a whole, otherwise only Wallflower's hooks inside it.
    private func removeEntries(from document: JSONText, where shouldRemove: (String) -> Bool) throws -> JSONText {
        var document = document
        var changed = true
        while changed {
            changed = false
            guard let hooks = document.root["hooks"], hooks.isObject else { return document }
            search: for member in hooks.members where member.node.isArray {
                for (index, element) in member.node.elements.enumerated() {
                    let commands = element.allStrings.filter(WallflowerCommand.isOurs)
                    guard commands.contains(where: shouldRemove) else { continue }
                    if let inner = element["hooks"], inner.isArray, inner.elements.contains(where: { $0.allStrings.filter(WallflowerCommand.isOurs).isEmpty }) {
                        // A group the person shares with their own hooks: only Wallflower's hook leaves it.
                        guard let innerIndex = inner.elements.firstIndex(where: { $0.allStrings.contains(where: { WallflowerCommand.isOurs($0) && shouldRemove($0) }) }) else { continue }
                        document = try JSONText(bytes: document.removingElement(of: inner, at: innerIndex))
                    } else {
                        document = try JSONText(bytes: document.removingElement(of: member.node, at: index))
                    }
                    changed = true
                    break search
                }
            }
        }
        return document
    }
}
