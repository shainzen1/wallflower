import SwiftUI
import WallflowerHookCore

/// "Which agents do you use?": Claude Code (built in, always on), every agent found on this Mac with
/// a box to tick (none ticked to begin with), the ones that can't work greyed with their reason, and
/// the supported ones not found in one line. Nothing is written here; Start shows the changes first.
struct WelcomeAgentsPage: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Which agents do you use?")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.agentChoices.enumerated()), id: \.element.id) { index, choice in
                        if index > 0 {
                            Rectangle().fill(WelcomeStyle.hairline).frame(height: 1)
                        }
                        WelcomeAgentRow(model: model, choice: choice)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: WelcomeStyle.agentsCardWidth)
            .frame(maxHeight: WelcomeStyle.agentsListMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(WelcomeStyle.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WelcomeStyle.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 22)
            VStack(spacing: 6) {
                if !model.missingAgents.isEmpty {
                    Text("Not found on this Mac: \(model.missingAgents.formatted(.list(type: .and))).")
                }
                Text(model.isPicked(.codex)
                    ? "Codex asks you to trust the hook once: type /hooks in Codex after Start."
                    : "Wallflower adds a small hook to each agent you tick. You can see and undo every change in Settings > Agents.")
            }
            .font(.system(size: 12))
            .foregroundStyle(WelcomeStyle.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: WelcomeStyle.agentsCardWidth)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        }
    }
}

/// One agent: a box, the name, and a line under it.
struct WelcomeAgentRow: View {
    @Bindable var model: WelcomeModel
    let choice: WelcomeModel.AgentChoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(choice.name, isOn: binding)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(choice.tool == nil)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(choice.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(choice.kind == .unavailable ? WelcomeStyle.tertiary : .white)
                    if choice.isExperimental {
                        Text("Experimental")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .foregroundStyle(WelcomeStyle.secondary)
                    }
                }
                Text(choice.note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WelcomeStyle.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WelcomeStyle.setUpInset)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if let tool = choice.tool { model.setPicked(tool, !model.isPicked(tool)) }
        }
        .accessibilityElement(children: .combine)
    }

    private var binding: Binding<Bool> {
        switch choice.kind {
        case .builtIn: .constant(true)
        case .unavailable: .constant(false)
        case .connectable(let tool): Binding(get: { model.isPicked(tool) }, set: { model.setPicked(tool, $0) })
        }
    }
}

/// After Start with agents ticked: every file each one changes, in one place, and the choice to
/// connect them and start, or go back.
struct WelcomeAgentConfirmation: View {
    let model: WelcomeModel
    let items: [WelcomeModel.AgentPlanItem]

    private var connectCount: Int {
        items.filter { if case .plan = $0 { true } else { false } }.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .onTapGesture {}
            VStack(alignment: .leading, spacing: 12) {
                Text(connectCount == 1 ? "Connect 1 agent" : "Connect \(connectCount) agents")
                    .font(.system(size: 20, weight: .semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            itemView(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 210)
                .fixedSize(horizontal: false, vertical: true)
                Text(AgentConsent.privacy + " A copy of each changed file is kept, and Settings > Agents undoes it all.")
                    .font(.system(size: 12))
                    .foregroundStyle(WelcomeStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Back") { model.cancelConfirmation() }
                        .buttonStyle(WelcomeSecondaryButtonStyle())
                    Spacer()
                    Button(connectCount == 0 ? "Start" : "Connect and start") { model.confirmStart() }
                        .buttonStyle(WelcomePrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(width: WelcomeStyle.agentsCardWidth + 40)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WelcomeStyle.hairline))
        }
    }

    @ViewBuilder
    private func itemView(_ item: WelcomeModel.AgentPlanItem) -> some View {
        switch item {
        case .plan(let plan):
            VStack(alignment: .leading, spacing: 5) {
                Text(AgentCatalog.entry(for: plan.tool)?.name ?? plan.tool.displayName)
                    .font(.system(size: 13, weight: .semibold))
                if plan.isEmpty {
                    Text("Already set up.")
                        .font(.system(size: 12))
                        .foregroundStyle(WelcomeStyle.tertiary)
                }
                ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                    Text((change.createsFile ? "New file " : "Adds to ") + AgentConsent.tilde(change.url, home: model.agentsHome))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(WelcomeStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    CodeBox(lines: change.addedLines, tint: WelcomeStyle.accent, maxHeight: 64)
                }
                if let extra = AgentConsent.afterConnect(plan.tool) {
                    Text(extra)
                        .font(.system(size: 12))
                        .foregroundStyle(WelcomeStyle.secondary)
                }
            }
        case .manual(let tool, let reason):
            VStack(alignment: .leading, spacing: 4) {
                Text(AgentCatalog.entry(for: tool)?.name ?? tool.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(reason) Set it up later in Settings > Agents.")
                    .font(.system(size: 12))
                    .foregroundStyle(WelcomeStyle.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension WelcomeStyle {
    /// "Which agents do you use?": the card's width, and how tall its list grows before it scrolls.
    static let agentsCardWidth: CGFloat = 420
    static let agentsListMaxHeight: CGFloat = 176
}
