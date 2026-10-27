import Foundation
import Testing
@testable import AgentOverview
@testable import WallflowerHookCore

@Suite("Welcome: look and agents")
@MainActor
struct WelcomeAgentsTests {
    @Test func theLookIsWrittenAsItChanges() {
        let model = WelcomeModel(page: WelcomeModel.lookPage, sessionSource: .desktop, faceStyle: .blob, colorMode: .status)
        var writes: [(FaceStyle, Theme.ColorMode)] = []
        model.onLookChange = { writes.append(($0, $1)) }
        model.faceStyle = .dotMatrix
        model.colorMode = .project
        model.colorMode = .project
        #expect(writes.map(\.0) == [.dotMatrix, .dotMatrix])
        #expect(writes.map(\.1) == [.status, .project], "an unchanged value writes nothing")
    }

    @Test func choicesComeFromWhatExistsOnly() throws {
        let environment = try TestHome.make(folders: [".claude", ".codex", ".copilot", "Applications/Cursor.app", ".kiro"])
        defer { TestHome.remove(environment) }
        let (choices, missing) = WelcomeModel.agentChoices(environment: environment)
        #expect(choices.first?.kind == .builtIn)
        #expect(choices.compactMap(\.tool) == [.codex, .copilot, .cursor])
        #expect(choices.contains { $0.id == "kiro" && $0.kind == .unavailable })
        #expect(choices.last?.name == "ChatGPT" && choices.last?.kind == .unavailable)
        #expect(missing.contains("Gemini CLI") && missing.contains("OpenCode") && !missing.contains("Codex"))
        #expect(TestHome.tree(environment.home).allSatisfy { !$0.contains("hooks") }, "detection writes nothing")
    }

    @Test func withoutCodexTheChatGPTLineSaysHowToGetIt() throws {
        let environment = try TestHome.make(folders: [".claude", ".copilot"])
        defer { TestHome.remove(environment) }
        let (choices, missing) = WelcomeModel.agentChoices(environment: environment)
        let codex = try #require(choices.first { $0.id == "codex" })
        #expect(codex.kind == .unavailable && codex.note == WelcomeModel.codexMissingNote)
        #expect(!missing.contains("Codex"), "named once, in its own row")
        #expect(choices.last?.name == "ChatGPT" && choices.last?.note == WelcomeModel.chatGPTWithoutCodexNote)
        #expect(choices.dropLast().last?.id == "codex", "right above ChatGPT")
    }

    @Test func startWithAgentsConfirmsFirst() {
        let model = WelcomeModel(page: WelcomeModel.pageCount, sessionSource: .desktop, launchAtLogin: false)
        let plan = ChangePlan(tool: .cursor, changes: [FileChange(url: URL(filePath: "/x/.cursor/hooks.json"), before: nil, after: Data("{}".utf8))])
        var asked: Set<AgentTool> = []
        model.planAgents = { tools in
            asked = tools
            return [.plan(plan), .manual(.gemini, "It has comments.")]
        }
        var outcomes: [WelcomeModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        model.setPicked(.cursor, true)
        model.setPicked(.gemini, true)
        model.primary()
        #expect(asked == [.cursor, .gemini])
        #expect(model.confirmation?.count == 2)
        #expect(outcomes.isEmpty, "nothing happens before the confirmation")
        model.dismiss()
        #expect(model.confirmation == nil, "Esc goes back to the page, it does not close")
        model.primary()
        model.confirmStart()
        #expect(outcomes == [.started(source: .desktop, launchAtLogin: false, agents: [plan])], "only the plans that can be written")
    }

    @Test func startWithoutAgentsStartsAtOnce() {
        let model = WelcomeModel(page: WelcomeModel.pageCount, sessionSource: .terminal, launchAtLogin: true)
        var outcomes: [WelcomeModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        model.primary()
        #expect(outcomes == [.started(source: .terminal, launchAtLogin: true)])
    }
}

@Suite("Agents: Show switches")
@MainActor
struct AgentShowSwitchTests {
    @Test func aHiddenToolsFacesAreLeftOut() {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil, externalFolder: URL(filePath: "/x"), hiddenTools: ["codex"])
        defer { store.stop() }
        let records = [
            ExternalSessionRecord(id: "codex-1", tool: "codex", status: .busy, updatedAt: TestSupport.millis(Date())),
            ExternalSessionRecord(id: "gemini-1", tool: "gemini", status: .idle, updatedAt: TestSupport.millis(Date())),
        ]
        store.reconcile(ExternalScanResult(records: records, presentIDs: ["codex-1", "gemini-1"]))
        #expect(store.sessions.map(\.key) == [.external("gemini-1")])
        #expect(store.presentExternalIDs == ["gemini-1"])
    }

    @Test func theSwitchIsStoredByToolID() throws {
        let suite = "AgentShowSwitchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = AgentsModel(environment: .fixture(home: URL(filePath: "/nonexistent")), settings: settings)
        model.setShown(.cursor, false)
        #expect(!model.isShown(.cursor) && model.isShown(.codex))
        #expect(AppSettings(defaults: defaults).hiddenAgentTools == ["cursor"])
        model.setShown(.cursor, true)
        #expect(AppSettings(defaults: defaults).hiddenAgentTools.isEmpty)
    }
}

struct AgentLaunchArgumentTests {
    @Test func agentArgumentsParse() {
        let arguments = LaunchArguments([
            "app", "--tools-home", "/tmp/fixture home", "--agent-sheet", "codex", "--connect-agents", "codex,gemini",
            "--disconnect-agents", "all", "--welcome-agents", "cursor", "--show-settings", "agents",
        ])
        #expect(arguments.toolsHome?.path == "/tmp/fixture home")
        #expect(arguments.agentSheet == "codex")
        #expect(arguments.connectAgents == ["codex", "gemini"])
        #expect(arguments.disconnectAgents == ["all"])
        #expect(arguments.welcomeAgents == ["cursor"])
        #expect(arguments.showSettings == .agents)
    }
}
