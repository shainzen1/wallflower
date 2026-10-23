import Foundation
import Testing
@testable import AgentOverview
@testable import WallflowerHookCore

/// A throwaway home folder for installer tests, with a space in its path (hook commands must quote
/// it). It can never be the real home: `make` checks that before any test touches it.
enum TestHome {
    static func make(folders: [String] = []) throws -> AgentEnvironment {
        let base = try TestSupport.makeTempFolder()
        let home = base.appending(path: "fixture home", directoryHint: .isDirectory)
        let real = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard !home.standardizedFileURL.path.hasPrefix(real + "/"), home.standardizedFileURL.path != real else {
            throw CocoaError(.fileWriteNoPermission)
        }
        for folder in folders {
            try FileManager.default.createDirectory(at: home.appending(path: folder), withIntermediateDirectories: true)
        }
        return AgentEnvironment.fixture(home: home)
    }

    static func remove(_ environment: AgentEnvironment) {
        try? FileManager.default.removeItem(at: environment.home.deletingLastPathComponent())
    }

    static func write(_ text: String, _ relative: String, in environment: AgentEnvironment) throws {
        let url = environment.path(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func read(_ relative: String, in environment: AgentEnvironment) -> String? {
        IntegrationStore.read(environment.path(relative)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Every file below a folder, relative paths, for "nothing else was written" checks.
    static func tree(_ folder: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        return Set(enumerator.compactMap { $0 as? String })
    }

    /// A stand-in helper binary (installers only copy it).
    static func fakeHelper() throws -> URL {
        let url = try TestSupport.makeTempFolder().appending(path: "wallflower-hook")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func connector(_ environment: AgentEnvironment) throws -> AgentConnector {
        AgentConnector(environment: environment, helperSource: try fakeHelper())
    }
}

@Suite("Agents: strict JSON editing")
struct JSONTextTests {
    @Test func rejectsWhatIsNotStrictJSON() {
        for text in [
            "{ // comment\n}", "{\"a\": 1,}", "[1, 2,]", "{\"a\": 1, \"a\": 2}", "\u{FEFF}{}", "{'a': 1}", "{\"a\": 01}", "{\"a\": .5}",
            "{\"a\": \"tab\there\"}", "{} {}", "", "{\"a\": NaN}", "/* x */ {}",
        ] {
            #expect(throws: JSONText.ParseError.self, "\(text)") { try JSONText(Data(text.utf8)) }
        }
        for text in ["{}", "[]", "{\"a\": [1, -2.5e3, true, false, null, \"\\u00e9\\ud83d\\ude00\"]}", " \n{\"x\": {\"y\": []}}\n"] {
            #expect((try? JSONText(Data(text.utf8))) != nil, "\(text)")
        }
    }

    @Test func appendThenRemoveRestoresEveryByte() throws {
        let originals = [
            "{\n    \"z\": 1,\n    \"a\": {\"keep\": \"order\"},\n    \"hooks\": {\n        \"Stop\": [\n            {\"command\": \"mine\"}\n        ]\n    }\n}\n",
            "{\"compact\": true, \"hooks\": {\"Stop\": [{\"command\": \"mine\"}]}}",
            "{\n\t\"tabs\": 1,\n\t\"hooks\": {\n\t\t\"Stop\": []\n\t}\n}",
        ]
        for original in originals {
            var document = try JSONText(Data(original.utf8))
            let list = try #require(document.node(at: ["hooks", "Stop"]))
            document = try JSONText(bytes: document.appendingElement(to: list, value: .object([("command", .string("ours"))])))
            #expect(document.node(at: ["hooks", "Stop"])?.elements.count == list.elements.count + 1)
            let hooks = try #require(document.node(at: ["hooks"]))
            document = try JSONText(bytes: document.appendingMember(to: hooks, key: "Start", value: .array([.int(1)])))
            let afterHooks = try #require(document.node(at: ["hooks"]))
            document = try JSONText(bytes: document.removingMember(of: afterHooks, at: afterHooks.members.count - 1))
            let afterList = try #require(document.node(at: ["hooks", "Stop"]))
            document = try JSONText(bytes: document.removingElement(of: afterList, at: afterList.elements.count - 1))
            if list.elements.isEmpty {
                #expect(String(decoding: document.data, as: UTF8.self) == original.replacingOccurrences(of: "[]", with: "[]"))
            } else {
                #expect(String(decoding: document.data, as: UTF8.self) == original)
            }
        }
    }

    @Test func insertedTextFollowsTheFilesIndentation() throws {
        let original = "{\n\t\"hooks\": {\n\t\t\"Stop\": [\n\t\t\t{\"command\": \"mine\"}\n\t\t]\n\t}\n}"
        let document = try JSONText(Data(original.utf8))
        let list = try #require(document.node(at: ["hooks", "Stop"]))
        let text = String(decoding: document.appendingElement(to: list, value: .object([("command", .string("ours"))])), as: UTF8.self)
        #expect(text.contains("{\"command\": \"mine\"},\n\t\t\t{\n\t\t\t\t\"command\": \"ours\"\n\t\t\t}\n\t\t]"))
    }
}

@Suite("Agents: installers")
struct AgentInstallerTests {
    static let hookFileTools: [AgentTool] = [.codex, .gemini, .cursor, .windsurf, .devin]

    static func folder(_ tool: AgentTool) -> String {
        switch tool {
        case .codex: ".codex"
        case .gemini: ".gemini"
        case .cursor: ".cursor"
        case .windsurf: ".codeium/windsurf"
        case .devin: ".config/devin"
        case .copilot: ".copilot"
        case .opencode: ".config/opencode"
        case .goose: ".config/goose"
        }
    }

    static func configPath(_ tool: AgentTool) -> String {
        AgentCatalog.integration(for: tool)!.primaryFile(in: .fixture(home: URL(filePath: "/x"))).path.replacingOccurrences(of: "/x/", with: "")
    }

    /// A config of the person's own, in each tool's format, with a hook of theirs on an event
    /// Wallflower also uses, odd spacing and keys in a non-alphabetical order.
    static func ownConfig(_ tool: AgentTool) -> String {
        switch tool {
        case .codex, .devin: """
            {
              "description": "my hooks",
              "hooks": {
                "Stop": [
                  {
                    "hooks": [ { "type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff", "timeout": 2 } ]
                  }
                ]
              }
            }

            """
        case .gemini: """
            {
                "theme": "Dracula",
                "model": { "name": "gemini-3-pro" },
                "hooks": {
                    "AfterAgent": [
                        { "matcher": "*", "hooks": [ { "name": "say-done", "type": "command", "command": "say done" } ] }
                    ]
                },
                "ui": { "hideBanner": true }
            }
            """
        case .cursor: """
            {"version": 1, "hooks": {"stop": [{"command": "./hooks/notify.sh"}], "afterFileEdit": [{"command": "./hooks/format.sh"}]}}
            """
        case .windsurf: """
            {
              "hooks": {
                "post_cascade_response": [
                  { "command": "echo done >> /tmp/log", "show_output": true }
                ]
              }
            }
            """
        case .copilot, .opencode, .goose: ""
        }
    }

    // MARK: Config edits

    @Test(arguments: hookFileTools)
    func connectingTwiceChangesNothingAndDisconnectRestoresEveryByte(tool: AgentTool) throws {
        let environment = try TestHome.make(folders: [Self.folder(tool)])
        defer { TestHome.remove(environment) }
        let path = Self.configPath(tool)
        let original = Self.ownConfig(tool)
        try TestHome.write(original, path, in: environment)
        let connector = try TestHome.connector(environment)
        let integration = try #require(AgentCatalog.integration(for: tool))
        #expect(integration.state(in: environment) == .available)

        try connector.connect(tool)
        let connected = try #require(TestHome.read(path, in: environment))
        #expect(integration.state(in: environment) == .connected)
        let document = try JSONText(Data(connected.utf8))
        #expect(connected.contains(environment.command(tool: tool, event: HookEvents.events(for: tool)[0]).replacingOccurrences(of: "/", with: "/")))
        // The person's hook and settings are still there, unchanged.
        for line in original.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty
            && !["}", "]", "},", "],"].contains(line.trimmingCharacters(in: .whitespaces)) && tool != .cursor {
            #expect(connected.contains(line.trimmingCharacters(in: CharacterSet(charactersIn: ","))), "kept: \(line)")
        }
        #expect(document.root.allStrings.filter(WallflowerCommand.isOurs).count == HookEvents.events(for: tool).count)

        // Idempotent.
        #expect(try connector.plan(tool).isEmpty)
        try connector.connect(tool)
        #expect(TestHome.read(path, in: environment) == connected)

        try connector.disconnect(tool)
        #expect(TestHome.read(path, in: environment) == original, "byte for byte")
        #expect(integration.state(in: environment) == .available)
        #expect(!FileManager.default.fileExists(atPath: environment.helperURL.path), "the last disconnect removes the helper")
    }

    @Test(arguments: hookFileTools)
    func aMissingFileIsCreatedAndDeletedAgain(tool: AgentTool) throws {
        let environment = try TestHome.make(folders: [Self.folder(tool)])
        defer { TestHome.remove(environment) }
        let before = TestHome.tree(environment.home)
        let connector = try TestHome.connector(environment)
        try connector.connect(tool)
        let text = try #require(TestHome.read(Self.configPath(tool), in: environment))
        #expect((try? JSONText(Data(text.utf8))) != nil)
        if tool == .cursor { #expect(text.hasPrefix("{\n  \"version\": 1,\n  \"hooks\": {")) }
        try connector.disconnect(tool)
        #expect(TestHome.read(Self.configPath(tool), in: environment) == nil)
        let after = TestHome.tree(environment.home).filter { !$0.hasPrefix("Library") }
        #expect(after == before, "nothing left behind outside Wallflower's own folder")
    }

    @Test(arguments: hookFileTools)
    func disconnectLeavesThePersonsLaterEditsAlone(tool: AgentTool) throws {
        let environment = try TestHome.make(folders: [Self.folder(tool)])
        defer { TestHome.remove(environment) }
        let path = Self.configPath(tool)
        try TestHome.write(Self.ownConfig(tool), path, in: environment)
        let connector = try TestHome.connector(environment)
        try connector.connect(tool)
        // The person adds a setting of their own at the end, after Wallflower's write.
        var document = try JSONText(Data(TestHome.read(path, in: environment)!.utf8))
        document = try JSONText(bytes: document.appendingMember(to: document.root, key: "addedLater", value: .bool(true)))
        try document.data.write(to: environment.path(path))

        try connector.disconnect(tool)
        let text = try #require(TestHome.read(path, in: environment))
        let result = try JSONText(Data(text.utf8))
        #expect(result.root["addedLater"]?.bool == true)
        #expect(!text.contains(HelperLayout.helperName), "every Wallflower entry is gone")
        // Without the later edit, the result is the original again.
        let withoutEdit = try JSONText(bytes: result.removingMember(of: result.root, at: result.root.members.count - 1))
        #expect(String(decoding: withoutEdit.data, as: UTF8.self) == Self.ownConfig(tool))
    }

    @Test func theUsersHooksSurviveInASharedGroup() throws {
        let environment = try TestHome.make(folders: [".codex"])
        defer { TestHome.remove(environment) }
        let connector = try TestHome.connector(environment)
        let command = environment.command(tool: .codex, event: "Stop")
        // Someone pasted Wallflower's Stop hook into their own group by hand.
        let shared = """
        {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say hi"}, {"type": "command", "command": "\(command)"}]}]}}
        """
        try TestHome.write(shared, ".codex/hooks.json", in: environment)
        try connector.connect(.codex)
        try connector.disconnect(.codex)
        let text = try #require(TestHome.read(".codex/hooks.json", in: environment))
        #expect(text.contains("say hi"))
        #expect(!text.contains(HelperLayout.helperName))
    }

    @Test func nonStrictFilesAreNeverWritten() throws {
        let environment = try TestHome.make(folders: [".gemini"])
        defer { TestHome.remove(environment) }
        let commented = "{\n  // my theme\n  \"theme\": \"Dracula\",\n}\n"
        try TestHome.write(commented, ".gemini/settings.json", in: environment)
        let connector = try TestHome.connector(environment)
        let error = #expect(throws: ManualSetup.self) { try connector.plan(.gemini) }
        #expect(error?.lines.contains(environment.command(tool: .gemini, event: "BeforeAgent")) == true)
        #expect(error?.lines.hasPrefix("\"hooks\": {") == true)
        guard case .manual = AgentCatalog.gemini.state(in: environment) else {
            Issue.record("expected the manual state")
            return
        }
        #expect(TestHome.read(".gemini/settings.json", in: environment) == commented)
    }

    @Test func aConcurrentChangeAbortsTheWrite() throws {
        let environment = try TestHome.make(folders: [".cursor"])
        defer { TestHome.remove(environment) }
        let original = Self.ownConfig(.cursor)
        try TestHome.write(original, ".cursor/hooks.json", in: environment)
        let connector = try TestHome.connector(environment)
        let plan = try connector.plan(.cursor)
        // Cursor (or the person) saves the file between the plan and the write.
        let changed = original.replacingOccurrences(of: "format.sh", with: "lint.sh")
        try TestHome.write(changed, ".cursor/hooks.json", in: environment)
        #expect(throws: IntegrationStore.ApplyError.changedSinceRead(environment.path(".cursor/hooks.json"))) { try connector.connect(plan) }
        #expect(TestHome.read(".cursor/hooks.json", in: environment) == changed)
        #expect(IntegrationStore(environment: environment).loadManifest().tools.isEmpty)
    }

    @Test func anOlderHelperPathIsRepaired() throws {
        let environment = try TestHome.make(folders: [".cursor"])
        defer { TestHome.remove(environment) }
        let old = """
        {"version": 1, "hooks": {"stop": [{"command": "/Applications/Wallflower.app/Contents/Helpers/wallflower-hook cursor stop"}]}}
        """
        try TestHome.write(old, ".cursor/hooks.json", in: environment)
        #expect(AgentCatalog.cursor.state(in: environment) == .outdated)
        try TestHome.connector(environment).connect(.cursor)
        let text = try #require(TestHome.read(".cursor/hooks.json", in: environment))
        #expect(!text.contains("/Applications/Wallflower.app"))
        #expect(AgentCatalog.cursor.state(in: environment) == .connected)
    }

    @Test func backupsGoToWallflowersFolderOnly() throws {
        let environment = try TestHome.make(folders: [".codex"])
        defer { TestHome.remove(environment) }
        try TestHome.write(Self.ownConfig(.codex), ".codex/hooks.json", in: environment)
        try TestHome.connector(environment).connect(.codex)
        #expect(TestHome.tree(environment.path(".codex")) == ["hooks.json"], "no backup or temp file beside the config")
        let backups = TestHome.tree(environment.backupsFolder.appending(path: "codex"))
        #expect(backups.count == 1 && backups.first?.hasPrefix("hooks.json.") == true)
        let record = try #require(IntegrationStore(environment: environment).loadManifest().tools["codex"])
        #expect(record.files.first?.createdFile == false)
        #expect(record.files.first?.beforeHash == IntegrationStore.hash(Data(Self.ownConfig(.codex).utf8)))
    }

    // MARK: Tool switches

    @Test func codexSettingsAreRespected() throws {
        #expect(CodexConfig.state(toml: "model = \"gpt-5\"\n[features]\nhooks = false\n") == .hooksDisabled("Hooks are turned off in your Codex settings ([features] hooks = false)."))
        #expect(CodexConfig.state(toml: "[features]\nhooks = true # on\n") == nil)
        if case .manual = CodexConfig.state(toml: "[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ncommand = \"say\"\n") {} else { Issue.record("inline hooks") }
        #expect(CodexConfig.state(toml: "# [hooks] in a comment\nmodel = \"x\"\n") == nil)

        let environment = try TestHome.make(folders: [".codex"])
        defer { TestHome.remove(environment) }
        let toml = "[features]\nhooks = false\n"
        try TestHome.write(toml, ".codex/config.toml", in: environment)
        try TestHome.connector(environment).connect(.codex)
        #expect(TestHome.read(".codex/config.toml", in: environment) == toml, "never turned back on")
        guard case .hooksDisabled = AgentCatalog.codex.state(in: environment) else {
            Issue.record("expected hooks disabled")
            return
        }
    }

    @Test func geminiSwitchesAreRespected() throws {
        let environment = try TestHome.make(folders: [".gemini"])
        defer { TestHome.remove(environment) }
        let settings = "{\n  \"hooksConfig\": { \"enabled\": false }\n}\n"
        try TestHome.write(settings, ".gemini/settings.json", in: environment)
        guard case .hooksDisabled = AgentCatalog.gemini.state(in: environment) else {
            Issue.record("expected hooks disabled")
            return
        }
        try TestHome.connector(environment).connect(.gemini)
        let text = try #require(TestHome.read(".gemini/settings.json", in: environment))
        #expect(try JSONText(Data(text.utf8)).node(at: ["hooksConfig", "enabled"])?.bool == false)
    }

    @Test func toolsThatNeverRanAreNotWrittenInto() throws {
        let environment = try TestHome.make(folders: ["Applications/Cursor.app"])
        defer { TestHome.remove(environment) }
        #expect(AgentCatalog.cursor.isInstalled(in: environment))
        guard case .needsFirstRun = AgentCatalog.cursor.state(in: environment) else {
            Issue.record("expected needs first run")
            return
        }
        #expect(throws: ManualSetup.self) { try TestHome.connector(environment).plan(.cursor) }
        #expect(!environment.exists(".cursor"))
        #expect(AgentCatalog.codex.state(in: environment) == .notInstalled)
    }

    // MARK: Drop-ins

    @Test(arguments: [AgentTool.copilot, .opencode, .goose])
    func dropInsAreOwnFilesOnly(tool: AgentTool) throws {
        let environment = try TestHome.make(folders: [Self.folder(tool)])
        defer { TestHome.remove(environment) }
        // A file of the person's own next to Wallflower's.
        let own: String = switch tool {
        case .copilot: ".copilot/hooks/mine.json"
        case .opencode: ".config/opencode/plugins/mine.js"
        default: ".agents/plugins/mine/plugin.json"
        }
        try TestHome.write("{\"mine\": true}", own, in: environment)
        let before = TestHome.tree(environment.home)
        let connector = try TestHome.connector(environment)
        let integration = try #require(AgentCatalog.integration(for: tool))
        #expect(integration.state(in: environment) == .available)
        try connector.connect(tool)
        #expect(integration.state(in: environment) == .connected)
        #expect(try connector.plan(tool).isEmpty, "idempotent")
        try connector.disconnect(tool)
        #expect(integration.state(in: environment) == .available)
        #expect(TestHome.read(own, in: environment) == "{\"mine\": true}")
        let after = TestHome.tree(environment.home).filter { !$0.hasPrefix("Library") }
        #expect(after == before.filter { !$0.hasPrefix("Library") })
    }

    @Test func copilotDropInIsValid() throws {
        let environment = try TestHome.make(folders: [".copilot"])
        defer { TestHome.remove(environment) }
        try TestHome.connector(environment).connect(.copilot)
        let document = try JSONText(Data(TestHome.read(".copilot/hooks/wallflower.json", in: environment)!.utf8))
        #expect(document.root.members.first?.key == "version")
        #expect(document.node(at: ["hooks", "notification"])?.elements.first?["bash"]?.string == environment.command(tool: .copilot, event: "notification"))
        #expect(document.node(at: ["hooks", "notification"])?.elements.first?["timeoutSec"] != nil)
    }

    @Test func gooseDropInHasAManifest() throws {
        let environment = try TestHome.make(folders: [".config/goose"])
        defer { TestHome.remove(environment) }
        try TestHome.connector(environment).connect(.goose)
        #expect(TestHome.read(".agents/plugins/wallflower/plugin.json", in: environment)?.contains("\"name\": \"wallflower\"") == true)
        let hooks = try JSONText(Data(TestHome.read(".agents/plugins/wallflower/hooks/hooks.json", in: environment)!.utf8))
        #expect(hooks.node(at: ["hooks", "Stop"])?.elements.first?["matcher"] == nil, "Goose skips a '*' matcher; none is written")
    }

    // MARK: Safety

    @Test func everyPlanStaysInsideTheFixtureHome() throws {
        let environment = try TestHome.make(folders: AgentTool.allCases.map(Self.folder))
        defer { TestHome.remove(environment) }
        let connector = try TestHome.connector(environment)
        for tool in AgentTool.allCases {
            let plan = try connector.plan(tool)
            #expect(!plan.isEmpty)
            for change in plan.changes {
                #expect(change.url.path.hasPrefix(environment.home.path + "/"), "\(change.url.path)")
            }
            try connector.connect(plan)
        }
        #expect(environment.helperURL.path.hasPrefix(environment.home.path))
        #expect(environment.sessionsFolder.path.hasPrefix(environment.home.path))
        #expect(connector.connectedTools == Set(AgentTool.allCases))
        #expect(connector.disconnectAll().isEmpty)
        #expect(connector.connectedTools.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: environment.path(".local").path), "the helper's folders go with the last tool")
    }

    @Test func commandsQuoteAHomeWithASpace() throws {
        let environment = try TestHome.make()
        defer { TestHome.remove(environment) }
        let command = environment.command(tool: .codex, event: "Stop")
        #expect(command.hasPrefix("'") && command.hasSuffix("wallflower-hook' codex Stop"))
        let plain = AgentEnvironment.fixture(home: URL(filePath: "/Users/demo"))
        #expect(plain.command(tool: .gemini, event: "AfterAgent") == "/Users/demo/.local/share/wallflower/bin/wallflower-hook gemini AfterAgent")
    }
}
