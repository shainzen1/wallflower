import AppKit
import Observation
import WallflowerHookCore

/// State of Settings > Agents: every agent's row, the consent sheet, the inline Undo and the Codex
/// trust check. Configs are read when the tab appears, when the window comes back to the front and
/// after every change; nothing watches or polls them.
@Observable @MainActor
final class AgentsModel {
    /// One row of the list.
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let tool: AgentTool?
        let installed: Bool
        /// nil for a coming-soon entry.
        let state: ConnectionState?
        let note: String
        let isExperimental: Bool
        let notePinned: Bool
    }

    /// What the sheet shows.
    enum Sheet: Identifiable, Equatable {
        /// The consent sheet: the files and the lines Connect adds.
        case connect(ChangePlan)
        /// Wallflower can't write: the lines to add by hand, with Copy.
        case manual(AgentTool, ManualSetup)
        /// The row menu's Show changes: Wallflower's lines in the file now.
        case changes(AgentTool, file: URL, lines: [String])
        /// Codex's one-time step.
        case codexTrustHelp
        /// Disconnect all, confirmed.
        case disconnectAll([AgentTool])

        var id: String {
            switch self {
            case .connect(let plan): "connect-\(plan.tool.rawValue)"
            case .manual(let tool, _): "manual-\(tool.rawValue)"
            case .changes(let tool, _, _): "changes-\(tool.rawValue)"
            case .codexTrustHelp: "codex-trust"
            case .disconnectAll: "disconnect-all"
            }
        }
    }

    let environment: AgentEnvironment
    let connector: AgentConnector
    let settings: AppSettings
    private(set) var rows: [Row] = []
    private(set) var hasClaudeCode = false
    var sheet: Sheet?
    /// The tool whose Connect can be undone right now, for `undoDuration` after it.
    private(set) var undoTool: AgentTool?
    /// The last failure, shown under the list until the next action.
    private(set) var message: String?
    private(set) var codexTrust: CodexTrust?
    private(set) var isCheckingTrust = false
    /// The Not installed and Not possible popovers are open.
    var showsNotInstalled = false
    var showsImpossible = false

    static let undoDuration: TimeInterval = 10
    @ObservationIgnored private var undoToken = UUID()

    init(environment: AgentEnvironment, settings: AppSettings, helperSource: URL? = HelperInstaller.bundledHelper) {
        self.environment = environment
        self.settings = settings
        connector = AgentConnector(environment: environment, helperSource: helperSource)
    }

    var installedRows: [Row] { rows.filter(\.installed) }
    var notInstalledRows: [Row] { rows.filter { !$0.installed } }
    var connectedTools: [AgentTool] {
        rows.compactMap { row in row.state == .connected || row.state == .outdated ? row.tool : nil }
    }

    /// Reads every tool's state again. `checkTrust` also asks Codex (once per call) when it is connected.
    func refresh(checkTrust: Bool = false) {
        hasClaudeCode = AgentCatalog.hasClaudeCode(in: environment)
        rows = AgentCatalog.entries.map { entry in
            let installed = entry.isInstalled(in: environment)
            return Row(
                id: entry.id, name: entry.name, tool: entry.tool, installed: installed,
                state: entry.integration.map { $0.state(in: environment) }, note: entry.note, isExperimental: entry.isExperimental,
                notePinned: entry.notePinned
            )
        }
        if checkTrust { checkCodexTrust() }
    }

    // MARK: Connect

    func requestConnect(_ tool: AgentTool) {
        message = nil
        do {
            let plan = try connector.plan(tool)
            if plan.isEmpty {
                try connector.connect(plan)
                refresh()
            } else {
                sheet = .connect(plan)
            }
        } catch let manual as ManualSetup {
            sheet = .manual(tool, manual)
        } catch {
            message = error.localizedDescription
        }
    }

    /// The consent sheet's Connect: writes the plan the person saw.
    func confirmConnect(_ plan: ChangePlan) {
        sheet = nil
        do {
            try connector.connect(plan)
            offerUndo(plan.tool)
        } catch {
            message = error.localizedDescription
        }
        refresh()
        if plan.tool == .codex { checkCodexTrust() }
    }

    func undo() {
        guard let tool = undoTool else { return }
        undoTool = nil
        disconnect(tool)
    }

    // MARK: Disconnect

    func disconnect(_ tool: AgentTool) {
        message = nil
        do {
            try connector.disconnect(tool)
        } catch let manual as ManualSetup {
            sheet = .manual(tool, manual)
        } catch {
            message = error.localizedDescription
        }
        if undoTool == tool { undoTool = nil }
        if tool == .codex { codexTrust = nil }
        refresh()
    }

    func requestDisconnectAll() {
        sheet = .disconnectAll(connectedTools)
    }

    func confirmDisconnectAll() {
        sheet = nil
        let failures = connector.disconnectAll()
        message = failures.isEmpty ? nil : failures.map { "\($0.0.displayName): \($0.1.localizedDescription)" }.joined(separator: "\n")
        undoTool = nil
        codexTrust = nil
        refresh()
    }

    // MARK: Row menu

    func showChanges(_ tool: AgentTool) {
        guard let integration = AgentCatalog.integration(for: tool) else { return }
        let file = integration.primaryFile(in: environment)
        let text = IntegrationStore.read(file).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let lines = tool == .opencode || tool == .copilot || tool == .goose
            ? text.components(separatedBy: "\n")
            : text.components(separatedBy: "\n").filter { $0.contains(HelperLayout.helperName) }
        sheet = .changes(tool, file: file, lines: lines)
    }

    func reveal(_ tool: AgentTool) {
        guard let file = AgentCatalog.integration(for: tool)?.primaryFile(in: environment) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Show switches

    func isShown(_ tool: AgentTool) -> Bool {
        !settings.hiddenAgentTools.contains(tool.rawValue)
    }

    func setShown(_ tool: AgentTool, _ shown: Bool) {
        if shown { settings.hiddenAgentTools.remove(tool.rawValue) } else { settings.hiddenAgentTools.insert(tool.rawValue) }
    }

    // MARK: Status lines

    /// The line under a row's name.
    func statusLine(_ row: Row) -> String {
        guard let state = row.state else { return row.installed ? row.note : row.note }
        switch state {
        case .notInstalled: return "Not installed"
        case .available: return "Installed · not connected"
        case .outdated: return "Connected with an older setup · update to repair it"
        case .needsFirstRun(let text): return text
        case .hooksDisabled(let text): return text
        case .manual(let text): return text
        case .failed(let text): return text
        case .connected:
            if row.tool == .codex {
                switch codexTrust {
                case .needsTrust?: return "Waiting for you to trust the hooks in Codex"
                case .disabled?: return "Connected · turned off in Codex's /hooks"
                case .notListed?: return "Connected · Codex doesn't list the hooks yet"
                case nil where isCheckingTrust: return "Connected · checking Codex…"
                default: break
                }
            }
            return "Connected"
        }
    }

    // MARK: Private

    private func offerUndo(_ tool: AgentTool) {
        undoTool = tool
        let token = UUID()
        undoToken = token
        // One shot, not a timer: the Undo button goes away once.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoDuration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.undoToken == token else { return }
                self.undoTool = nil
            }
        }
    }

    /// Asks Codex's app server once whether the hooks are trusted (only while Codex is connected).
    private func checkCodexTrust() {
        guard rows.first(where: { $0.tool == .codex })?.state == .connected, !isCheckingTrust else { return }
        isCheckingTrust = true
        let environment = environment
        Task { @MainActor [weak self] in
            let trust = await CodexTrustCheck.run(environment: environment)
            self?.codexTrust = trust
            self?.isCheckingTrust = false
        }
    }
}
