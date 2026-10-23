import Foundation
import WallflowerHookCore

/// Codex runs a hook only after the person trusted it once (`/hooks` in the CLI, Settings > Hooks in
/// the ChatGPT app). Whether that happened is answered by Codex's own app server: `hooks/list` reports
/// every hook with its `trustStatus`. Wallflower asks only when the Agents tab opens or right after
/// Connect, never on a timer, and the server process lives for that one exchange.
enum CodexTrust: Equatable, Sendable {
    /// Every Wallflower hook is trusted (or managed) and enabled.
    case trusted
    /// At least one is new or changed and waits for the person's review in Codex.
    case needsTrust
    /// At least one is turned off in Codex.
    case disabled
    /// Codex doesn't list them (hooks off, or Codex not reading `hooks.json`).
    case notListed
    /// No answer: no `codex` found, a timeout, warnings, an unknown status.
    case unverified
}

enum CodexTrustCheck {
    /// The JSON-RPC lines sent to `codex app-server --stdio` (newline-delimited, no `jsonrpc` header).
    static func requests(home: URL) -> [String] {
        let cwd = JSONLiteral.string(home.path).render(indent: "", unit: "", compact: true)
        return [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"wallflower","title":null,"version":"1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized","params":{}}"#,
            "{\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\(cwd)]}}",
        ]
    }

    /// Reads the `hooks/list` reply (the line with `"id": 2`) for the hooks Wallflower wrote: each
    /// one matched by its event and exact command, as Codex lists them.
    static func parse(response: Data, expected: [(event: String, command: String)]) -> CodexTrust {
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = object["result"] as? [String: Any], let data = result["data"] as? [[String: Any]] else { return .unverified }
        var hooks: [[String: Any]] = []
        for entry in data {
            if let errors = entry["errors"] as? [Any], !errors.isEmpty { return .unverified }
            hooks += entry["hooks"] as? [[String: Any]] ?? []
        }
        var verdict = CodexTrust.trusted
        for (event, command) in expected {
            let match = hooks.first { hook in
                (hook["eventName"] as? String)?.lowercased() == event.lowercased() && (hook["command"] as? String) == command
            }
            guard let match else { return .notListed }
            if match["enabled"] as? Bool == false {
                verdict = .disabled
                continue
            }
            switch match["trustStatus"] as? String {
            case "trusted", "managed": continue
            case "untrusted", "modified": if verdict == .trusted { verdict = .needsTrust }
            default: return .unverified
            }
        }
        return verdict
    }

    /// Where a `codex` binary may be: inside the ChatGPT (or old Codex) app first, then the usual
    /// command-line places. A fixture home only looks inside itself.
    static func candidateBinaries(environment: AgentEnvironment) -> [URL] {
        var apps = environment.applicationFolders.flatMap { folder in
            ["ChatGPT.app", "Codex.app"].map { folder.appending(path: $0) }
        }
        if !environment.isFixture {
            apps += ["ChatGPT.app", "Codex.app"].map { environment.home.appending(path: "Applications/\($0)") }
        }
        var binaries = apps.flatMap { app in
            [app.appending(path: "Contents/Resources/codex"), app.appending(path: "Contents/Resources/codex-cli/bin/codex")]
        }
        binaries.append(environment.home.appending(path: ".local/bin/codex"))
        if !environment.isFixture {
            binaries += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map { URL(filePath: $0) }
        }
        return binaries.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs the check: starts the app server, sends the three requests, waits for the `hooks/list`
    /// reply (at most `timeout`), stops the server.
    static func run(environment: AgentEnvironment, timeout: TimeInterval = 5) async -> CodexTrust {
        guard let binary = candidateBinaries(environment: environment).first else { return .unverified }
        let expected = HookEvents.events(for: .codex).map { ($0, environment.command(tool: .codex, event: $0)) }
        guard let reply = await AppServerExchange.run(
            binary: binary, arguments: ["app-server", "--stdio"], home: environment.home,
            lines: requests(home: environment.home), replyID: 2, timeout: timeout
        ) else { return .unverified }
        return parse(response: reply, expected: expected)
    }
}

/// One request and reply exchange with a JSON-lines server process.
enum AppServerExchange {
    /// Starts `binary`, writes `lines` (one at a time: the second only after the reply to the first),
    /// returns the first stdout line whose `id` is `replyID`, and terminates the process.
    static func run(binary: URL, arguments: [String], home: URL, lines: [String], replyID: Int, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(binary: binary, arguments: arguments, home: home, lines: lines, replyID: replyID, timeout: timeout))
            }
        }
    }

    private static func runBlocking(binary: URL, arguments: [String], home: URL, lines: [String], replyID: Int, timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = home
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.appending(path: ".codex").path
        environment["HOME"] = home.path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        defer {
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }
        let reader = LineReader(handle: output.fileHandleForReading)
        func send(_ line: String) -> Bool {
            (try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))) != nil
        }
        // initialize, wait for its reply, then the rest.
        guard let first = lines.first, send(first), reader.reply(id: 1, deadline: deadline) != nil else { return nil }
        for line in lines.dropFirst() where !send(line) { return nil }
        return reader.reply(id: replyID, deadline: deadline)
    }

    /// Reads stdout lines on a background thread and hands out replies by id.
    private final class LineReader: @unchecked Sendable {
        private let condition = NSCondition()
        private var buffer = Data()
        private var replies: [Int: Data] = [:]
        private var closed = false

        init(handle: FileHandle) {
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                self?.append(chunk)
                if chunk.isEmpty { handle.readabilityHandler = nil }
            }
        }

        private func append(_ chunk: Data) {
            condition.lock()
            defer {
                condition.broadcast()
                condition.unlock()
            }
            guard !chunk.isEmpty else {
                closed = true
                return
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? Int {
                    replies[id] = Data(line)
                }
            }
            if buffer.count > 4 << 20 { buffer.removeAll() }
        }

        func reply(id: Int, deadline: Date) -> Data? {
            condition.lock()
            defer { condition.unlock() }
            while replies[id] == nil, !closed {
                guard condition.wait(until: deadline) else { return nil }
            }
            return replies[id]
        }
    }
}
