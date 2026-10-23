import Foundation
import Testing
@testable import AgentOverview
@testable import WallflowerHookCore

/// The Codex trust check, against canned `hooks/list` replies shaped like the app server's
/// (`HookMetadata`: `eventName` in camelCase, `command`, `enabled`, `trustStatus`). The real `codex`
/// is never run: the end-to-end case starts a shell script that plays the server.
@Suite("Agents: Codex trust check")
struct CodexTrustTests {
    static let home = URL(filePath: "/Users/demo")
    static func expected(_ environment: AgentEnvironment = .fixture(home: home)) -> [(event: String, command: String)] {
        HookEvents.events(for: .codex).map { ($0, environment.command(tool: .codex, event: $0)) }
    }

    static var expected: [(event: String, command: String)] { expected() }

    /// A reply listing every Wallflower hook with `status` (and `enabled`), plus one hook of the person's.
    static func reply(
        _ environment: AgentEnvironment = .fixture(home: home), status: (String) -> String, enabled: (String) -> Bool = { _ in true }, errors: String = "[]"
    ) -> Data {
        let hooks = expected(environment).map { event, command in
            let camel = event.prefix(1).lowercased() + event.dropFirst()
            let quoted = JSONLiteral.string(command).render(indent: "", unit: "", compact: true)
            return """
            {"key":"user:\(camel):0","eventName":"\(camel)","matcher":null,"handlerType":"command","command":\(quoted),"async":false,\
            "timeoutSec":5,"statusMessage":null,"sourcePath":"/Users/demo/.codex/hooks.json","source":"user","enabled":\(enabled(event)),\
            "isManaged":false,"currentHash":"abc","trustStatus":"\(status(event))"}
            """
        }
        let own = #"{"key":"user:stop:1","eventName":"stop","command":"say done","enabled":true,"source":"user","trustStatus":"untrusted"}"#
        return Data("""
        {"id":2,"result":{"data":[{"cwd":"/Users/demo","hooks":[\((hooks + [own]).joined(separator: ","))],"warnings":[],"errors":\(errors)}]}}
        """.utf8)
    }

    @Test func readsEveryTrustState() {
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { _ in "trusted" }), expected: Self.expected) == .trusted)
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { _ in "managed" }), expected: Self.expected) == .trusted)
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { $0 == "Stop" ? "untrusted" : "trusted" }), expected: Self.expected) == .needsTrust)
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { $0 == "Stop" ? "modified" : "trusted" }), expected: Self.expected) == .needsTrust)
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { _ in "trusted" }, enabled: { $0 != "SessionEnd" }), expected: Self.expected) == .disabled)
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { _ in "someday" }), expected: Self.expected) == .unverified)
        let errors = #"[{"path":"/Users/demo/.codex/hooks.json","message":"bad"}]"#
        #expect(CodexTrustCheck.parse(response: Self.reply(status: { _ in "trusted" }, errors: errors), expected: Self.expected) == .unverified)
        let empty = Data(#"{"id":2,"result":{"data":[{"cwd":"/Users/demo","hooks":[],"warnings":[],"errors":[]}]}}"#.utf8)
        #expect(CodexTrustCheck.parse(response: empty, expected: Self.expected) == .notListed)
        #expect(CodexTrustCheck.parse(response: Data(#"{"id":2,"error":{"code":-32601,"message":"no"}}"#.utf8), expected: Self.expected) == .unverified)
        #expect(CodexTrustCheck.parse(response: Data("garbage".utf8), expected: Self.expected) == .unverified)
    }

    @Test func requestsAreOneJSONObjectPerLine() throws {
        let lines = CodexTrustCheck.requests(home: URL(filePath: "/Users/demo x"))
        #expect(lines.count == 3)
        for line in lines {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(object["jsonrpc"] == nil)
        }
        #expect(lines[2].contains(#""method":"hooks/list","params":{"cwds":["/Users/demo x"]}"#))
    }

    @Test func aFixtureHomeOnlyFindsItsOwnCodex() throws {
        let environment = try TestHome.make()
        defer { TestHome.remove(environment) }
        #expect(CodexTrustCheck.candidateBinaries(environment: environment).isEmpty, "never /opt/homebrew or /Applications")
    }

    /// The whole exchange against a stand-in server: a shell script that answers `initialize`, then
    /// `hooks/list` with a canned reply.
    @Test func runsTheExchangeAgainstAStandInServer() async throws {
        let environment = try TestHome.make()
        defer { TestHome.remove(environment) }
        let fixed = String(decoding: Self.reply(environment, status: { _ in "untrusted" }), as: UTF8.self)
        let script = environment.path(".local/bin/codex")
        try TestHome.write("""
        #!/bin/sh
        [ "$1" = "app-server" ] && [ "$2" = "--stdio" ] || exit 64
        while IFS= read -r line; do
          case "$line" in
            *'"id":1'*) printf '%s\\n' '{"method":"configWarning","params":{}}' '{"id":1,"result":{"userAgent":"stand-in"}}' ;;
            *'"id":2'*) cat <<'REPLY'
        \(fixed)
        REPLY
              exit 0 ;;
          esac
        done
        """, ".local/bin/codex", in: environment)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        #expect(CodexTrustCheck.candidateBinaries(environment: environment) == [script])
        let trust = await CodexTrustCheck.run(environment: environment, timeout: 5)
        #expect(trust == .needsTrust)
    }
}
