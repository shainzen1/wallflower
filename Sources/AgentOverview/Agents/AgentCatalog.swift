import Foundation
import WallflowerHookCore

/// Every agent the Agents tab and the welcome list: the ones Wallflower connects, the ones that come
/// later, and the ones that can't work, each with the one line the UI shows. Formats and sources per
/// tool: `docs/agents.md`.
enum AgentCatalog {
    /// What the list shows for one agent.
    struct Entry: Identifiable, Sendable {
        enum Kind: Sendable {
            /// Wallflower connects it.
            case integration(any AgentIntegration)
            /// Not yet: the line says why. Detected like an integration, never written to.
            case comingSoon(detectPaths: [String], appNames: [String])
        }

        let id: String
        let name: String
        let kind: Kind
        /// Under the name while connected (what the faces can show), or the coming-soon reason.
        let note: String
        /// Marked experimental in the list.
        var isExperimental = false
        /// The note stays under the row whatever the state: what the faces can't show, or what
        /// Codex also covers. Other notes only go into the consent sheet and the welcome.
        var notePinned = false

        var tool: AgentTool? {
            if case .integration(let integration) = kind { return integration.tool }
            return nil
        }

        var integration: (any AgentIntegration)? {
            if case .integration(let integration) = kind { return integration }
            return nil
        }

        func isInstalled(in environment: AgentEnvironment) -> Bool {
            switch kind {
            case .integration(let integration): integration.isInstalled(in: environment)
            case .comingSoon(let paths, let names): paths.contains(where: environment.exists) || (!names.isEmpty && environment.appLookup([], names))
            }
        }
    }

    /// One "not possible" line.
    struct Impossible: Identifiable, Sendable {
        let id: String
        let name: String
        let reason: String
    }

    static let codex = HookFileIntegration(
        tool: .codex, configPath: ".codex/hooks.json", toolFolder: ".codex",
        appBundleIDs: ["com.openai.codex"], appNames: ["ChatGPT", "Codex"],
        // Seconds. SessionEnd and Interrupt allow 1 to 3.
        style: .group(name: nil, matcher: nil, timeout: { ["SessionEnd", "Interrupt"].contains($0) ? 3 : 5 }),
        extraState: { environment, _ in CodexConfig.state(home: environment.home) }
    )

    static let copilot = DropInIntegration(tool: .copilot, toolFolder: ".copilot") { environment in
        let events = HookEvents.events(for: .copilot)
        let hooks = JSONLiteral.object(events.map { event in
            (event, .array([.object([
                ("type", .string("command")), ("bash", .string(environment.command(tool: .copilot, event: event))), ("timeoutSec", .int(5)),
            ])]))
        })
        let root = JSONLiteral.object([("version", .int(1)), ("hooks", hooks)])
        return [(".copilot/hooks/wallflower.json", Data((root.render(indent: "", unit: "  ", compact: false) + "\n").utf8))]
    }

    static let gemini = HookFileIntegration(
        tool: .gemini, configPath: ".gemini/settings.json", toolFolder: ".gemini", detectPaths: [".gemini/settings.json", ".gemini/oauth_creds.json", ".gemini/tmp"],
        // Milliseconds.
        style: .group(name: "wallflower", matcher: "*", timeout: { _ in 5000 }),
        extraState: { _, document in GeminiConfig.state(document) }
    )

    static let cursor = HookFileIntegration(
        tool: .cursor, configPath: ".cursor/hooks.json", toolFolder: ".cursor",
        appBundleIDs: ["com.todesktop.230313mzl4w4u92"], appNames: ["Cursor"],
        style: .flat(extra: [("timeout", .int(5))]), newFilePrefix: [("version", .int(1))]
    )

    static let opencode = DropInIntegration(tool: .opencode, toolFolder: ".config/opencode") { environment in
        // OpenCode 1.x loads `plugin/` and `plugins/`; an existing `plugin/` is used, else `plugins/`.
        let folder = environment.exists(".config/opencode/plugin") && !environment.exists(".config/opencode/plugins") ? "plugin" : "plugins"
        return [(".config/opencode/\(folder)/wallflower.js", Data(OpenCodePlugin.source(sessionsFolder: environment.sessionsFolder).utf8))]
    }

    static let windsurf = HookFileIntegration(
        tool: .windsurf, configPath: ".codeium/windsurf/hooks.json", toolFolder: ".codeium/windsurf",
        appBundleIDs: ["com.exafunction.windsurf"], appNames: ["Windsurf"],
        style: .flat(extra: [("show_output", .bool(false))])
    )

    static let goose = DropInIntegration(tool: .goose, toolFolder: ".config/goose", appBundleIDs: ["com.block.goose"], appNames: ["Goose"]) { environment in
        let manifest = JSONLiteral.object([
            ("name", .string("wallflower")), ("version", .string("1.0.0")),
            ("description", .string("Shows Goose sessions as faces at the edge of the screen (Wallflower).")),
        ])
        let events = HookEvents.events(for: .goose)
        let hooks = JSONLiteral.object([("hooks", .object(events.map { event in
            (event, .array([.object([("hooks", .array([.object([
                ("type", .string("command")), ("command", .string(environment.command(tool: .goose, event: event))), ("timeout", .int(5)),
            ])]))])]))
        }))])
        func text(_ value: JSONLiteral) -> Data { Data((value.render(indent: "", unit: "  ", compact: false) + "\n").utf8) }
        return [(".agents/plugins/wallflower/plugin.json", text(manifest)), (".agents/plugins/wallflower/hooks/hooks.json", text(hooks))]
    }

    static let devin = HookFileIntegration(
        tool: .devin, configPath: ".config/devin/config.json", toolFolder: ".config/devin",
        style: .group(name: nil, matcher: nil, timeout: { _ in 5 })
    )

    /// The list, in the order shown (installed ones move to the top in the UI).
    static let entries: [Entry] = [
        Entry(id: "codex", name: "Codex", kind: .integration(codex), note: "Also covers Codex in the ChatGPT app and in VS Code.", notePinned: true),
        Entry(id: "copilot", name: "GitHub Copilot", kind: .integration(copilot), note: "Copilot CLI, and Copilot's agent in VS Code."),
        Entry(id: "gemini", name: "Gemini CLI", kind: .integration(gemini), note: "Applies to new Gemini sessions."),
        Entry(id: "cursor", name: "Cursor", kind: .integration(cursor), note: "Working and done only: Cursor doesn't report approval prompts.", notePinned: true),
        Entry(id: "opencode", name: "OpenCode", kind: .integration(opencode), note: "OpenCode 1.x. Applies after restarting OpenCode."),
        Entry(id: "windsurf", name: "Windsurf", kind: .integration(windsurf), note: "Working and done only: Windsurf doesn't report approval prompts.", notePinned: true),
        Entry(id: "devin", name: "Devin CLI", kind: .integration(devin), note: "Applies to new Devin sessions."),
        Entry(id: "goose", name: "Goose", kind: .integration(goose), note: "Working and done only. Goose's hooks are new.", isExperimental: true, notePinned: true),
        Entry(id: "amp", name: "Amp", kind: .comingSoon(detectPaths: [".config/amp"], appNames: []),
              note: "Coming soon: Amp's plugin API is new and Wallflower hasn't been tested against it yet."),
        Entry(id: "kiro", name: "Kiro CLI", kind: .comingSoon(detectPaths: [".kiro"], appNames: ["Kiro"]),
              note: "Coming soon: Kiro doesn't document what its hooks receive yet."),
        Entry(id: "aider", name: "Aider", kind: .comingSoon(detectPaths: [".aider.conf.yml"], appNames: []),
              note: "Coming soon: Aider only reports when a reply is done, not when it starts working."),
        Entry(id: "antigravity", name: "Antigravity CLI", kind: .comingSoon(detectPaths: [".gemini/antigravity-cli"], appNames: ["Antigravity"]),
              note: "Coming soon: Antigravity's hooks are new and not settled yet."),
    ]

    static func entry(for tool: AgentTool) -> Entry? {
        entries.first { $0.tool == tool }
    }

    static func integration(for tool: AgentTool) -> (any AgentIntegration)? {
        entry(for: tool)?.integration
    }

    /// What can't work, with the one line the UI shows. ChatGPT first: it's the question people ask.
    static let impossible: [Impossible] = [
        Impossible(id: "chatgpt", name: "ChatGPT chats", reason: "ChatGPT doesn't share chat status with other apps. Codex in ChatGPT works: connect Codex."),
        Impossible(id: "claude-chats", name: "Claude app chats", reason: "Only Claude Code sessions report their status. Regular Claude chats don't."),
        Impossible(id: "zed", name: "Zed", reason: "Zed has no way for other apps to see its agent's status yet."),
        Impossible(id: "warp", name: "Warp's agent", reason: "Warp keeps agent status inside Warp. Agents you run in Warp's terminal work."),
        Impossible(id: "roo", name: "Roo Code", reason: "Roo Code has no hooks Wallflower could use."),
        Impossible(id: "cline", name: "Cline", reason: "Cline is changing its hook system; support comes once it settles."),
        Impossible(id: "cloud", name: "Cloud agents", reason: "Cloud agents run on a server, so there's nothing on your Mac to watch."),
    ]

    /// `~/.claude` exists: Claude Code is native, no setup.
    static func hasClaudeCode(in environment: AgentEnvironment) -> Bool {
        environment.exists(".claude")
    }
}

/// The two Codex settings that matter, read from `~/.codex/config.toml` line by line (no TOML
/// library: only table headers and two keys are looked at).
enum CodexConfig {
    /// `[features] hooks = false` (or the old `codex_hooks`): hooks are off, and Wallflower says so
    /// instead of turning them on. Inline `[hooks]` tables: a second hook source Codex warns about,
    /// so the person adds Wallflower's lines themselves.
    static func state(home: URL) -> ConnectionState? {
        guard let data = try? Data(contentsOf: home.appending(path: ".codex/config.toml")) else { return nil }
        return state(toml: String(decoding: data, as: UTF8.self))
    }

    static func state(toml: String) -> ConnectionState? {
        var table = ""
        var inlineHooks = false
        for rawLine in toml.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
                if table == "hooks" || table.hasPrefix("hooks.") { inlineHooks = true }
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = table.isEmpty ? parts[0] : "\(table).\(parts[0])"
            if ["features.hooks", "features.codex_hooks"].contains(key), parts[1] == "false" {
                return .hooksDisabled("Hooks are turned off in your Codex settings ([features] hooks = false).")
            }
            if key == "hooks" || key.hasPrefix("hooks.") { inlineHooks = true }
        }
        return inlineHooks ? .manual("Your config.toml already defines hooks, and Codex warns when hooks.json adds a second set.") : nil
    }
}

/// Gemini's switches in `settings.json`: `hooksConfig.enabled = false` turns every hook off, and
/// `hooksConfig.disabled` lists hook names turned off by `/hooks`.
enum GeminiConfig {
    static func state(_ document: JSONText?) -> ConnectionState? {
        guard let config = document?.root["hooksConfig"] else { return nil }
        if config["enabled"]?.bool == false {
            return .hooksDisabled("Hooks are turned off in your Gemini settings (hooksConfig.enabled).")
        }
        if config["disabled"]?.elements.contains(where: { $0.string == "wallflower" }) == true {
            return .hooksDisabled("Wallflower's hooks are turned off in Gemini (/hooks).")
        }
        return nil
    }
}
