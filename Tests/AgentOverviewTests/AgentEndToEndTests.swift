import Foundation
import Testing
@testable import AgentOverview
@testable import WallflowerHookCore

/// Connect in a fixture home with the real helper, run the commands exactly as the tools would (from
/// the config files Wallflower wrote, through a shell), watch the sessions folder, disconnect, and
/// compare every config with its original bytes.
@Suite("Agents: end to end in a fixture home")
struct AgentEndToEndTests {
    /// The hook commands a config holds for one event, read back from the written file.
    static func commands(_ tool: AgentTool, event: String, in environment: AgentEnvironment) throws -> [String] {
        let integration = try #require(AgentCatalog.integration(for: tool))
        let file: URL = tool == .copilot ? environment.path(".copilot/hooks/wallflower.json") : integration.primaryFile(in: environment)
        let document = try JSONText(Data(contentsOf: file))
        let entries = try #require(document.node(at: ["hooks", event])).elements
        return entries.flatMap(\.allStrings).filter(WallflowerCommand.isOurs)
    }

    /// Runs a command the way the tools do (`sh -c`), the payload on stdin; returns stdout + stderr.
    /// Off the cooperative pool (`TestSupport.offThePool`): the command blocks until it exits.
    @discardableResult
    static func shell(_ command: String, stdin: Data) async throws -> String {
        try await TestSupport.offThePool {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = ["PATH": "/usr/bin:/bin"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            try process.run()
            try? input.fileHandleForWriting.write(contentsOf: stdin)
            try? input.fileHandleForWriting.close()
            let out = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: out, as: UTF8.self) + (process.terminationStatus == 0 ? "" : "exit \(process.terminationStatus)")
        }
    }

    @Test func fiveToolsConnectReportAndDisconnect() async throws {
        let helper = try #require(AgentHookTests.builtHelper)
        let environment = try TestHome.make(folders: [".codex", ".gemini", ".cursor", ".copilot", ".config/opencode"])
        defer { TestHome.remove(environment) }
        try FileManager.default.createDirectory(at: environment.supportFolder, withIntermediateDirectories: true)
        // Existing configs of the person's for two of them.
        let codexOriginal = AgentInstallerTests.ownConfig(.codex)
        let geminiOriginal = AgentInstallerTests.ownConfig(.gemini)
        try TestHome.write(codexOriginal, ".codex/hooks.json", in: environment)
        try TestHome.write(geminiOriginal, ".gemini/settings.json", in: environment)
        let connector = AgentConnector(environment: environment, helperSource: helper)
        for tool in [AgentTool.codex, .gemini, .cursor, .copilot, .opencode] {
            try connector.connect(tool)
            #expect(AgentCatalog.integration(for: tool)?.state(in: environment) == .connected, "\(tool)")
        }
        #expect(FileManager.default.isExecutableFile(atPath: environment.helperURL.path))

        let sessions = environment.sessionsFolder
        func status(_ id: String) -> String? {
            (try? Data(contentsOf: sessions.appending(path: "\(id).json"))).flatMap { ExternalSessionScanner.decode($0) }
                .map { $0.status.rawValue + ($0.waitingFor.map { ":\($0)" } ?? "") }
        }
        let steps: [(AgentTool, String, String, String, String?)] = [
            (.codex, "UserPromptSubmit", "UserPromptSubmit", "codex-019a3c1e-codex-thread", "busy"),
            (.codex, "PermissionRequest", "PermissionRequest", "codex-019a3c1e-codex-thread", "waiting:permission"),
            (.codex, "Stop", "Stop", "codex-019a3c1e-codex-thread", "idle"),
            (.gemini, "BeforeAgent", "BeforeAgent", "gemini-gem-5f2a", "busy"),
            (.gemini, "Notification", "Notification", "gemini-gem-5f2a", "waiting:permission"),
            (.cursor, "beforeSubmitPrompt", "beforeSubmitPrompt", "cursor-c0ffee-cursor", "busy"),
            (.cursor, "stop", "stop", "cursor-c0ffee-cursor", "idle"),
            (.copilot, "userPromptSubmitted", "userPromptSubmitted", "copilot-cp-7781", "busy"),
            (.copilot, "notification", "notification-elicitation", "copilot-cp-7781", "waiting:question"),
            (.copilot, "agentStop", "agentStop", "copilot-cp-7781", "idle"),
            (.codex, "SessionEnd", "SessionEnd", "codex-019a3c1e-codex-thread", nil),
        ]
        for (tool, event, fixture, id, expected) in steps {
            let commands = try Self.commands(tool, event: event, in: environment)
            #expect(commands.count == 1, "\(tool) \(event)")
            for command in commands {
                let output = try await Self.shell(command, stdin: AgentHookTests.payload(tool.rawValue, fixture))
                #expect(output.isEmpty, "\(command) printed \(output)")
            }
            #expect(status(id) == expected, "\(tool) \(event)")
        }
        #expect(!AgentHookTests.allText(sessions).contains(AgentHookTests.canary))

        #expect(connector.disconnectAll().isEmpty)
        #expect(TestHome.read(".codex/hooks.json", in: environment) == codexOriginal)
        #expect(TestHome.read(".gemini/settings.json", in: environment) == geminiOriginal)
        #expect(TestHome.read(".cursor/hooks.json", in: environment) == nil)
        #expect(TestHome.tree(environment.path(".copilot")).isEmpty)
        #expect(TestHome.tree(environment.path(".config/opencode")).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: environment.helperURL.path))
    }

    static var node: URL? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)).appending(path: "node") }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The OpenCode plugin, loaded by node and fed bus events shaped like OpenCode 1.x's.
    @Test(.enabled(if: node != nil, "needs node on the PATH"))
    func openCodePluginWritesStatusesFromTheEventBus() async throws {
        let node = try #require(Self.node)
        let environment = try TestHome.make(folders: [".config/opencode"])
        defer { TestHome.remove(environment) }
        try FileManager.default.createDirectory(at: environment.supportFolder, withIntermediateDirectories: true)
        try TestHome.connector(environment).connect(.opencode)
        let plugin = environment.path(".config/opencode/plugins/wallflower.js")
        let driver = environment.home.appending(path: "driver.mjs")
        let script = """
        import { pathToFileURL } from "node:url";
        import fs from "node:fs";
        const mod = await import(pathToFileURL(process.argv[2]).href);
        if (Object.keys(mod).length !== 1) throw new Error("one export only");
        const hooks = await mod.WallflowerPlugin({ directory: "/Users/demo/Developer/notes" });
        const sessions = process.argv[3];
        const read = () => { try { return JSON.parse(fs.readFileSync(sessions + "/opencode-ses_1.json", "utf8")); } catch { return null; } };
        const out = [];
        const send = async (type, properties) => { await hooks.event({ event: { type, properties } }); const r = read(); out.push(r ? r.status + (r.waitingFor ? ":" + r.waitingFor : "") : "none"); };
        await send("session.created", { info: { id: "ses_1", title: "WF-SECRET-CANARY" } });
        await send("session.created", { info: { id: "ses_child", parentID: "ses_1" } });
        await send("session.status", { sessionID: "ses_1", status: { type: "busy" } });
        await send("permission.asked", { id: "per_1", sessionID: "ses_1", permission: "bash", patterns: ["WF-SECRET-CANARY"], metadata: {}, always: [] });
        await send("permission.replied", { sessionID: "ses_1", requestID: "per_1", reply: "once" });
        await send("question.asked", { id: "q_1", sessionID: "ses_1", questions: [{ question: "WF-SECRET-CANARY?" }] });
        await send("question.replied", { sessionID: "ses_1", requestID: "q_1" });
        await send("session.status", { sessionID: "ses_child", status: { type: "busy" } });
        await send("session.idle", { sessionID: "ses_1" });
        const pid = read()?.pid === process.pid;
        const leaked = fs.readdirSync(sessions).some((name) => fs.readFileSync(sessions + "/" + name, "utf8").includes("WF-SECRET-CANARY"));
        await send("session.deleted", { info: { id: "ses_1" } });
        console.log(JSON.stringify({ out, pid, leaked, files: fs.readdirSync(sessions) }));
        """
        try Data(script.utf8).write(to: driver)
        let arguments = [driver.path, plugin.path, environment.sessionsFolder.path]
        // Off the cooperative pool (`TestSupport.offThePool`): node blocks until it exits.
        let (status, data) = try await TestSupport.offThePool {
            let process = Process()
            process.executableURL = node
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }
        let text = String(decoding: data, as: UTF8.self)
        #expect(status == 0, "\(text)")
        let result = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "\(text)")
        #expect(result["out"] as? [String] == [
            "idle", "idle", "busy", "waiting:permission", "busy", "waiting:question", "busy", "busy", "idle", "none",
        ])
        #expect(result["pid"] as? Bool == true, "the face lives as long as OpenCode")
        #expect(result["leaked"] as? Bool == false, "no title or question text in the file")
        #expect(result["files"] as? [String] == [], "no child session file, nothing left after delete")
    }
}
