import Darwin
import Foundation
import Testing
@testable import AgentOverview
@testable import WallflowerHookCore

/// A process table for the owner walk: pid to parent, executable path, arguments.
struct FakeProcessTree: ProcessInspector {
    struct Process: Sendable {
        var parent: pid_t
        var path: String
        var arguments: [String] = []
    }

    var processes: [pid_t: Process]

    func parent(of pid: pid_t) -> pid_t? { processes[pid]?.parent }
    func executablePath(of pid: pid_t) -> String? { processes[pid]?.path }
    func name(of pid: pid_t) -> String? { processes[pid].map { ($0.path as NSString).lastPathComponent } }
    func arguments(of pid: pid_t) -> [String] { processes[pid]?.arguments ?? [] }

    /// hook shell (300) -> codex (200) -> zsh (150) -> Terminal (100)
    static let codexCLI = FakeProcessTree(processes: [
        300: Process(parent: 200, path: "/bin/zsh"),
        200: Process(parent: 150, path: "/opt/homebrew/bin/codex"),
        150: Process(parent: 100, path: "/bin/zsh"),
        100: Process(parent: 1, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    ])

    /// hook shell (300) -> codex app-server (210) -> ChatGPT (110)
    static let codexDesktop = FakeProcessTree(processes: [
        300: Process(parent: 210, path: "/bin/zsh"),
        210: Process(parent: 110, path: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        110: Process(parent: 1, path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
    ])

    /// hook shell (300) -> node gemini (220) -> zsh (150) -> Terminal (100)
    static let geminiCLI = FakeProcessTree(processes: [
        300: Process(parent: 220, path: "/bin/bash"),
        220: Process(parent: 150, path: "/opt/homebrew/Cellar/node/24.1.0/bin/node", arguments: ["node", "/opt/homebrew/bin/gemini"]),
        150: Process(parent: 100, path: "/bin/zsh"),
        100: Process(parent: 1, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    ])

    /// hook shell (300) -> Cursor Helper (Plugin) (230) -> Cursor (130)
    static let cursorIDE = FakeProcessTree(processes: [
        300: Process(parent: 230, path: "/bin/zsh"),
        230: Process(parent: 130, path: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)"),
        130: Process(parent: 1, path: "/Applications/Cursor.app/Contents/MacOS/Cursor"),
    ])

    /// hook shell (300) -> node copilot (240) -> zsh (150) -> Terminal (100)
    static let copilotCLI = FakeProcessTree(processes: [
        300: Process(parent: 240, path: "/bin/bash"),
        240: Process(parent: 150, path: "/usr/local/bin/node", arguments: ["node", "/usr/local/lib/node_modules/@github/copilot/index.js"]),
        150: Process(parent: 100, path: "/bin/zsh"),
        100: Process(parent: 1, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    ])

    /// Nothing recognisable: an orphaned shell.
    static let empty = FakeProcessTree(processes: [300: Process(parent: 1, path: "/bin/sh")])
}

@Suite("Agents: the hook helper")
struct AgentHookTests {
    static let canary = "WF-SECRET-CANARY"
    static let bundleIDs = ["/Applications/Cursor.app": "com.todesktop.230313mzl4w4u92", "/Applications/ChatGPT.app": "com.openai.codex"]

    static func payload(_ tool: String, _ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/agents/\(tool)") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    /// A temp home with Wallflower's support folder, so the helper may create `sessions/` in it.
    static func makeHome() throws -> (home: URL, sessions: URL) {
        let home = try TestSupport.makeTempFolder()
        try FileManager.default.createDirectory(at: HelperLayout.supportFolder(home: home), withIntermediateDirectories: true)
        return (home, HelperLayout.sessionsFolder(home: home))
    }

    @discardableResult
    static func run(
        _ tool: AgentTool, _ event: String, fixture: String? = nil, folder: URL, tree: FakeProcessTree, now: Date = Date()
    ) throws -> [String: Any]? {
        let stdin = try payload(tool.rawValue, fixture ?? event)
        HookRunner.run(arguments: [tool.rawValue, event], stdin: stdin, sessionsFolder: folder, start: 300, inspector: tree, now: now) {
            bundleIDs[$0]
        }
        return nil
    }

    static func files(_ folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
    }

    static func record(_ folder: URL, _ id: String) throws -> ExternalSessionRecord {
        let data = try Data(contentsOf: folder.appending(path: "\(id).json"))
        return try #require(ExternalSessionScanner.decode(data))
    }

    /// Every byte of every file in `folder`, to look for leaked text.
    static func allText(_ folder: URL) -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.map { String(decoding: (try? Data(contentsOf: folder.appending(path: $0))) ?? Data(), as: UTF8.self) }.joined()
    }

    // MARK: Per tool

    @Test func codexCLIRunsThroughEveryStatus() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let id = "codex-019a3c1e-codex-thread"
        try Self.run(.codex, "SessionStart", folder: folder, tree: .codexCLI)
        var record = try Self.record(folder, id)
        #expect(record.status == .idle)
        #expect(record.tool == "codex")
        #expect(record.cwd == "/Users/demo/Developer/parser")
        #expect(record.pid == 200, "the codex process, not the hook's shell")
        #expect(record.open == nil, "a CLI session is found through its pid")

        try Self.run(.codex, "UserPromptSubmit", folder: folder, tree: .codexCLI)
        #expect(try Self.record(folder, id).status == .busy)
        try Self.run(.codex, "PermissionRequest", folder: folder, tree: .codexCLI)
        record = try Self.record(folder, id)
        #expect(record.status == .waiting && record.waitingFor == "permission")
        try Self.run(.codex, "PostToolUse", folder: folder, tree: .codexCLI)
        #expect(try Self.record(folder, id).status == .busy, "an approved tool clears the wait")
        try Self.run(.codex, "Stop", folder: folder, tree: .codexCLI)
        #expect(try Self.record(folder, id).status == .idle)
        try Self.run(.codex, "Interrupt", folder: folder, tree: .codexCLI)
        #expect(try Self.record(folder, id).status == .idle)
        try Self.run(.codex, "SessionEnd", folder: folder, tree: .codexCLI)
        #expect(Self.files(folder).isEmpty, "the end deletes the file")
        #expect(!Self.allText(folder).contains(Self.canary))
    }

    @Test func codexInTheChatGPTAppOpensItsThread() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.run(.codex, "UserPromptSubmit", folder: folder, tree: .codexDesktop)
        let record = try Self.record(folder, "codex-019a3c1e-codex-thread")
        #expect(record.pid == 210)
        #expect(record.open == .url(URL(string: "codex://threads/019a3c1e-codex-thread")!))
    }

    @Test func geminiMapsPermissionAndKeepsEventOrder() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let id = "gemini-gem-5f2a"
        for event in ["SessionStart", "BeforeAgent", "Notification"] {
            try Self.run(.gemini, event, folder: folder, tree: .geminiCLI)
        }
        var record = try Self.record(folder, id)
        #expect(record.status == .waiting && record.waitingFor == "permission")
        #expect(record.pid == 220, "node running gemini")
        // BeforeAgent again, but stamped before the notification: an out-of-order event changes nothing.
        try Self.run(.gemini, "BeforeAgent", folder: folder, tree: .geminiCLI)
        record = try Self.record(folder, id)
        #expect(record.status == .waiting)
        try Self.run(.gemini, "AfterTool", folder: folder, tree: .geminiCLI)
        #expect(try Self.record(folder, id).status == .busy)
        try Self.run(.gemini, "AfterAgent", folder: folder, tree: .geminiCLI)
        record = try Self.record(folder, id)
        #expect(record.status == .idle)
        #expect(record.statusUpdatedAt == 1_792_659_630_000, "the status clock is the event's own time")
        #expect(!Self.allText(folder).contains(Self.canary))
        try Self.run(.gemini, "SessionEnd", folder: folder, tree: .geminiCLI)
        #expect(Self.files(folder).isEmpty)
    }

    @Test func cursorDropsTheEmailAndOpensCursor() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.run(.cursor, "sessionStart", folder: folder, tree: .cursorIDE)
        try Self.run(.cursor, "beforeSubmitPrompt", folder: folder, tree: .cursorIDE)
        let record = try Self.record(folder, "cursor-c0ffee-cursor")
        #expect(record.status == .busy)
        #expect(record.cwd == "/Users/demo/Developer/shop", "the first workspace root")
        #expect(record.pid == 130, "Cursor itself, not its plugin helper")
        #expect(record.open == .app(bundleID: "com.todesktop.230313mzl4w4u92"))
        let text = Self.allText(folder)
        #expect(!text.contains(Self.canary) && !text.contains("@example.com"))
        try Self.run(.cursor, "stop", folder: folder, tree: .cursorIDE)
        #expect(try Self.record(folder, "cursor-c0ffee-cursor").status == .idle)
        try Self.run(.cursor, "sessionEnd", folder: folder, tree: .cursorIDE)
        #expect(Self.files(folder).isEmpty)
    }

    @Test func copilotHasQuestionsAndPermissions() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let id = "copilot-cp-7781"
        try Self.run(.copilot, "sessionStart", folder: folder, tree: .copilotCLI)
        try Self.run(.copilot, "userPromptSubmitted", folder: folder, tree: .copilotCLI)
        #expect(try Self.record(folder, id).status == .busy)
        try Self.run(.copilot, "notification", fixture: "notification-permission", folder: folder, tree: .copilotCLI)
        var record = try Self.record(folder, id)
        #expect(record.status == .waiting && record.waitingFor == "permission")
        #expect(record.pid == 240)
        try Self.run(.copilot, "postToolUse", folder: folder, tree: .copilotCLI)
        #expect(try Self.record(folder, id).status == .busy)
        try Self.run(.copilot, "notification", fixture: "notification-elicitation", folder: folder, tree: .copilotCLI)
        record = try Self.record(folder, id)
        #expect(record.status == .waiting && record.waitingFor == "question")
        // A background agent's idle notification is not this session's turn ending.
        try Self.run(.copilot, "notification", fixture: "notification-agent-idle", folder: folder, tree: .copilotCLI)
        #expect(try Self.record(folder, id).status == .waiting)
        try Self.run(.copilot, "agentStop", folder: folder, tree: .copilotCLI)
        #expect(try Self.record(folder, id).status == .idle)
        #expect(!Self.allText(folder).contains(Self.canary))
        try Self.run(.copilot, "sessionEnd", folder: folder, tree: .copilotCLI)
        #expect(Self.files(folder).isEmpty)
    }

    @Test func copilotInVSCodeSendsPascalCaseFields() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.run(.copilot, "userPromptSubmitted", fixture: "vscode-UserPromptSubmit", folder: folder, tree: .empty)
        let record = try Self.record(folder, "copilot-vs-4410")
        #expect(record.status == .busy)
        #expect(record.cwd == "/Users/demo/Developer/web")
        #expect(record.pid == nil, "no owner found: the ten minute rule applies")
    }

    @Test func windsurfDevinAndGoose() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try Self.run(.windsurf, "pre_user_prompt", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "windsurf-traj-91ab").status == .busy)
        try Self.run(.windsurf, "post_cascade_response", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "windsurf-traj-91ab").status == .idle)
        try Self.run(.devin, "UserPromptSubmit", folder: folder, tree: .empty)
        try Self.run(.devin, "PermissionRequest", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "devin-devin-aa12").waitingFor == "permission")
        try Self.run(.devin, "Stop", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "devin-devin-aa12").status == .idle)
        try Self.run(.goose, "UserPromptSubmit", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "goose-goose-20261022_1").status == .busy)
        try Self.run(.goose, "Stop", folder: folder, tree: .empty)
        #expect(try Self.record(folder, "goose-goose-20261022_1").status == .idle)
        #expect(!Self.allText(folder).contains(Self.canary))
    }

    // MARK: Robustness

    @Test func garbageAndUnknownsWriteNothing() throws {
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let inputs: [([String], Data)] = [
            ([], Data()),
            (["codex"], Data("not json".utf8)),
            (["nosuchtool", "Stop"], Data(#"{"session_id":"x"}"#.utf8)),
            (["codex", "PreToolUse"], Data(#"{"session_id":"x"}"#.utf8)),
            (["codex", "Stop"], Data("[1,2,3]".utf8)),
            (["codex", "Stop"], Data(repeating: UInt8(ascii: " "), count: HookPayload.maxBytes + 10)),
        ]
        for (arguments, stdin) in inputs {
            HookRunner.run(arguments: arguments, stdin: stdin, sessionsFolder: folder, start: 300, inspector: FakeProcessTree.empty)
        }
        #expect(Self.files(folder).isEmpty)
    }

    @Test func aMissingWallflowerFolderStaysMissing() throws {
        let home = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = HelperLayout.sessionsFolder(home: home)
        try Self.run(.codex, "UserPromptSubmit", folder: folder, tree: .codexCLI)
        #expect(!FileManager.default.fileExists(atPath: HelperLayout.supportFolder(home: home).path), "Wallflower uninstalled: nothing is created")
    }

    @Test func fileIDsAreSafeFileNames() {
        #expect(HookRunner.fileID(tool: .codex, sessionID: "thr_123", ownerPid: nil) == "codex-thr_123")
        #expect(HookRunner.fileID(tool: .cursor, sessionID: "../../etc/passwd", ownerPid: nil) == "cursor-..-..-etc-passwd")
        #expect(HookRunner.fileID(tool: .gemini, sessionID: "/", ownerPid: 42) == "gemini-pid42")
        #expect(HookRunner.fileID(tool: .gemini, sessionID: nil, ownerPid: nil) == nil)
        let long = HookRunner.fileID(tool: .copilot, sessionID: String(repeating: "a", count: 300), ownerPid: nil)
        #expect(long?.count == 128)
    }

    @Test func sessionsFolderFollowsTheHelpersHome() {
        let folder = HookRunner.sessionsFolder(environment: [:], executablePath: "/Users/demo x/.local/share/wallflower/bin/wallflower-hook")
        #expect(folder.path == "/Users/demo x/Library/Application Support/Wallflower/sessions")
        let override = HookRunner.sessionsFolder(environment: ["WALLFLOWER_SESSIONS_DIR": "/tmp/s"], executablePath: "/x/wallflower-hook")
        #expect(override.path == "/tmp/s")
    }

    @Test func ownerWalkRecognisesAppsOnly() {
        #expect(OwnerResolver.mainExecutableApp("/Applications/Cursor.app/Contents/MacOS/Cursor") == "/Applications/Cursor.app")
        #expect(OwnerResolver.mainExecutableApp("/Applications/Cursor.app/Contents/Frameworks/H.app/Contents/MacOS/H") == nil)
        #expect(OwnerResolver.mainExecutableApp("/opt/homebrew/bin/codex") == nil)
        // A CLI tool without its process on the way up is not pinned to the terminal app.
        let owner = OwnerResolver.resolve(tool: .codex, start: 300, inspector: FakeProcessTree.geminiCLI)
        #expect(owner == SessionOwner())
    }

    // MARK: The built helper

    /// The `wallflower-hook` executable SwiftPM built next to the tests (the resources bundle sits
    /// in the products folder or inside the `.xctest` bundle there).
    static var builtHelper: URL? {
        var folder = Bundle.module.bundleURL.deletingLastPathComponent()
        for _ in 0..<4 {
            let url = folder.appending(path: HelperLayout.helperName)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    @Test func theBuiltHelperPrintsNothingAndExitsZero() async throws {
        let helper = try #require(Self.builtHelper, "swift build builds wallflower-hook next to the tests")
        let (home, folder) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // A helper that stopped reading must fail this test, not kill the test process.
        signal(SIGPIPE, SIG_IGN)
        let cases: [([String], Data)] = [
            (["codex", "UserPromptSubmit"], try Self.payload("codex", "UserPromptSubmit")),
            (["gemini", "Notification"], try Self.payload("gemini", "Notification")),
            (["codex", "Stop"], Data("{{{ garbage".utf8)),
            (["nosuchtool"], Data()),
            ([], Data()),
            (["copilot", "agentStop"], Data(repeating: UInt8(ascii: "x"), count: 600 * 1024)),
        ]
        for (arguments, stdin) in cases {
            // Off the cooperative pool (`TestSupport.offThePool`): the helper blocks until it exits.
            let (status, reason, out, err, elapsed) = try await TestSupport.offThePool {
                let process = Process()
                process.executableURL = helper
                process.arguments = arguments
                process.environment = ["WALLFLOWER_SESSIONS_DIR": folder.path, "PATH": "/usr/bin:/bin"]
                let input = Pipe(), output = Pipe(), error = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = error
                let started = Date()
                try process.run()
                try? input.fileHandleForWriting.write(contentsOf: stdin)
                try? input.fileHandleForWriting.close()
                let out = output.fileHandleForReading.readDataToEndOfFile()
                let err = error.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, process.terminationReason, out, err, Date().timeIntervalSince(started))
            }
            #expect(status == 0, "\(arguments)")
            #expect(reason == .exit)
            #expect(out.isEmpty && err.isEmpty, "prints nothing: \(arguments)")
            #expect(elapsed < 1.5)
        }
        let record = try Self.record(folder, "codex-019a3c1e-codex-thread")
        #expect(record.status == .busy)
        #expect(try Self.record(folder, "gemini-gem-5f2a").status == .waiting)
        #expect(!Self.allText(folder).contains(Self.canary), "no prompt text lands in the sessions folder")
    }
}

@Suite("Agents: the owner walk")
struct OwnerWalkTests {
    @Test func onlyTheToolsOwnAppOwnsASession() {
        // A Cursor hook run from some other app (another agent's app, a terminal) has no owner.
        let elsewhere = FakeProcessTree(processes: [
            300: .init(parent: 250, path: "/bin/sh"),
            250: .init(parent: 1, path: "/Applications/Other.app/Contents/MacOS/Other"),
        ])
        #expect(OwnerResolver.resolve(tool: .cursor, start: 300, inspector: elsewhere) == SessionOwner())
        let vscode = FakeProcessTree(processes: [
            300: .init(parent: 260, path: "/bin/bash"),
            260: .init(parent: 160, path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"),
            160: .init(parent: 1, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code"),
        ])
        let owner = OwnerResolver.resolve(tool: .copilot, start: 300, inspector: vscode) { $0.hasSuffix("Visual Studio Code.app") ? "com.microsoft.VSCode" : nil }
        #expect(owner == SessionOwner(pid: 160, appBundleID: "com.microsoft.VSCode"))
    }
}
