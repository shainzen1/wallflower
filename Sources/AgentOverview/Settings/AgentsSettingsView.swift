import SwiftUI
import WallflowerHookCore

/// The Agents tab: Claude Code (built in), the agents Wallflower connects with their state, the ones
/// not on this Mac, the ones that can't work and why, and the switch for every other tool's files.
/// Connect asks first (the consent sheet lists every line it adds); Disconnect lives in each row's
/// menu and in Disconnect all, so no switch ever edits a config file.
struct AgentsSettingsView: View {
    @Bindable var model: AgentsModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(model.hasClaudeCode ? "Built in" : "Not found")
                        .foregroundStyle(.secondary)
                } label: {
                    AgentRowLabel(name: "Claude Code", status: model.hasClaudeCode
                        ? "Shows sessions from: \(settings.sessionSource.title) (General)"
                        : "Install Claude Code and its sessions show here.")
                }
            }

            Section {
                ForEach(model.installedRows) { row in
                    AgentRowView(model: model, row: row)
                }
                if model.installedRows.isEmpty {
                    Text("No other agents found on this Mac.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Agents on this Mac")
            } footer: {
                if let message = model.message {
                    SettingsFootnote(message)
                        .foregroundStyle(.red)
                } else {
                    SettingsFootnote("Wallflower adds a small hook to each agent you connect. It only learns that a session is working, waiting or done, never your prompts or replies.")
                }
            }

            Section {
                AgentListRow(
                    title: "Not installed", isPresented: $model.showsNotInstalled,
                    names: model.notInstalledRows.map(\.name),
                    items: model.notInstalledRows.map { ($0.name, $0.state == nil ? $0.note : "Not installed", $0.isExperimental) }
                )
                AgentListRow(
                    title: "Not possible yet", isPresented: $model.showsImpossible,
                    names: AgentCatalog.impossible.map(\.name),
                    items: AgentCatalog.impossible.map { ($0.name, $0.reason, false) }
                )
            }

            Section {
                Toggle("Sessions from other tools", isOn: $settings.externalSessions)
                LabeledContent("Disconnect every agent") {
                    Button("Disconnect all…", role: .destructive) { model.requestDisconnectAll() }
                        .disabled(model.connectedTools.isEmpty)
                }
            } footer: {
                SettingsFootnote("Any tool or script can show up by writing a small session file; see docs/external-sessions.md. Disconnect all removes every hook Wallflower added and restores each file it changed.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .sheet(item: $model.sheet) { sheet in
            AgentSheetView(model: model, sheet: sheet)
        }
        .onAppear { model.refresh(checkTrust: true) }
    }
}

/// Name over a one-line status.
struct AgentRowLabel: View {
    let name: String
    let status: String
    var dimmed = false
    var experimental = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(name)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                if experimental {
                    Text("Experimental")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One installed agent: its state, and what can be done from here.
struct AgentRowView: View {
    let model: AgentsModel
    let row: AgentsModel.Row

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) { trailing }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AgentRowLabel(name: row.name, status: model.statusLine(row), experimental: row.isExperimental)
                if row.notePinned, row.state != nil {
                    Text(row.note)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let tool = row.tool, let state = row.state {
            switch state {
            case .available:
                Button("Connect…") { model.requestConnect(tool) }
            case .outdated:
                Button("Update…") { model.requestConnect(tool) }
                menu(tool)
            case .manual:
                Button("Add lines…") { model.requestConnect(tool) }
            case .connected, .hooksDisabled:
                if model.undoTool == tool {
                    Button("Undo") { model.undo() }
                }
                if tool == .codex, model.codexTrust == .needsTrust {
                    Button("How") { model.sheet = .codexTrustHelp }
                }
                Text("Show")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Show", isOn: Binding(get: { model.isShown(tool) }, set: { model.setShown(tool, $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("Show this agent's faces. Its hooks stay connected either way.")
                    .accessibilityLabel("Show \(row.name)'s faces")
                menu(tool)
            case .needsFirstRun, .notInstalled, .failed:
                EmptyView()
            }
        }
    }

    private func menu(_ tool: AgentTool) -> some View {
        Menu {
            Button("Show changes…") { model.showChanges(tool) }
            Button("Reveal file in Finder") { model.reveal(tool) }
            Divider()
            Button("Disconnect", role: .destructive) { model.disconnect(tool) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More for \(row.name)")
    }
}

/// A title, the names in one line, and an info button whose popover lists each with its line. A
/// popover rather than a disclosure, so the window keeps its height.
struct AgentListRow: View {
    let title: String
    @Binding var isPresented: Bool
    let names: [String]
    let items: [(name: String, status: String, experimental: Bool)]

    var body: some View {
        LabeledContent {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Why: \(title)")
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        AgentRowLabel(name: item.name, status: item.status, experimental: item.experimental)
                    }
                }
                .padding(16)
                .frame(width: 380, alignment: .leading)
            }
        } label: {
            AgentRowLabel(name: title, status: names.isEmpty ? "None" : names.joined(separator: ", "))
        }
    }
}

/// The Agents tab's sheets: consent, add-by-hand, show changes, the Codex step, disconnect all.
struct AgentSheetView: View {
    let model: AgentsModel
    let sheet: AgentsModel.Sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .connect(let plan):
            Text("Connect \(AgentCatalog.entry(for: plan.tool)?.name ?? plan.tool.displayName)")
                .font(.headline)
            AgentPlanView(plan: plan, home: model.environment.home)
            Text(AgentConsent.privacy)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let extra = AgentConsent.afterConnect(plan.tool) {
                Text(extra)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons(primary: "Connect") { model.confirmConnect(plan) }
        case .manual(let tool, let setup):
            Text("Add \(tool.displayName)'s hooks yourself")
                .font(.headline)
            Text(setup.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !setup.lines.isEmpty {
                Text("Merge these lines into \(AgentConsent.tilde(setup.file, home: model.environment.home)):")
                    .font(.callout)
                CodeBox(lines: setup.lines.components(separatedBy: "\n"), tint: nil)
                HStack {
                    Button("Copy") { model.copy(setup.lines) }
                    Spacer()
                    Button("Done") { model.sheet = nil }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    Spacer()
                    Button("OK") { model.sheet = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .changes(let tool, let file, let lines):
            Text("\(tool.displayName): what Wallflower added")
                .font(.headline)
            Text(AgentConsent.tilde(file, home: model.environment.home))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            CodeBox(lines: lines, tint: nil)
            HStack {
                Button("Reveal in Finder") { model.reveal(tool) }
                Spacer()
                Button("Done") { model.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
        case .codexTrustHelp:
            Text("Trust Wallflower's hooks in Codex")
                .font(.headline)
            Text(AgentConsent.codexTrust)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { model.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
        case .disconnectAll(let tools):
            Text("Disconnect every agent?")
                .font(.headline)
            Text("Wallflower removes its hooks from \(tools.map(\.displayName).formatted(.list(type: .and))), deletes the files it created and puts back each file it changed. Your own settings and hooks stay as they are.")
                .fixedSize(horizontal: false, vertical: true)
            buttons(primary: "Disconnect all", role: .destructive) { model.confirmDisconnectAll() }
        }
    }

    private func buttons(primary: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { model.sheet = nil }
                .keyboardShortcut(.cancelAction)
            Button(primary, role: role, action: action)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// The files of a plan, each with its path and the lines it adds (green) or removes (red).
struct AgentPlanView: View {
    let plan: ChangePlan
    let home: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(change.createsFile ? "New file" : change.deletesFile ? "Deletes" : "Adds to")
                            .font(.callout.weight(.medium))
                        Text(AgentConsent.tilde(change.url, home: home))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    CodeBox(lines: change.addedLines, tint: .green)
                }
            }
            if plan.changes.contains(where: { $0.before != nil }) {
                Text("A copy of each changed file is kept in Wallflower's folder, and Disconnect puts it back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Monospaced lines in a rounded box, scrolling past a few lines, with an optional tint (`+` lines).
struct CodeBox: View {
    let lines: [String]
    var tint: Color?
    var maxHeight: CGFloat = 150

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text((tint == nil ? "" : "+ ") + line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tint ?? .primary)
                        .fixedSize()
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: min(maxHeight, CGFloat(lines.count) * 15 + 18))
        .background((tint ?? .secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The shared wording of the consent sheet and the welcome's confirmation.
enum AgentConsent {
    static let privacy = "Wallflower only learns that a session is working, waiting or done. It never sees your prompts or replies."
    static let codexTrust = "Codex runs a new hook only after you trust it once. In a Codex chat type /hooks and trust the Wallflower entries, or in the ChatGPT app open Settings > Hooks. You only do this once."

    /// What follows Connect for a tool, if anything.
    static func afterConnect(_ tool: AgentTool) -> String? {
        switch tool {
        case .codex: "One more step in Codex: type /hooks and trust Wallflower's hooks."
        case .opencode: "Restart OpenCode to load the plugin."
        case .gemini, .devin: "Applies to new sessions."
        case .goose: "Experimental: restart Goose to load the plugin."
        case .copilot, .cursor, .windsurf: nil
        }
    }

    /// `/Users/x/.codex/hooks.json` as `~/.codex/hooks.json`.
    static func tilde(_ url: URL, home: URL) -> String {
        let path = url.path
        return path.hasPrefix(home.path + "/") ? "~" + path.dropFirst(home.path.count) : path
    }
}
