import SwiftUI

/// Name and status of one row, shown inside the bulge beside the face (left of it on the right edge,
/// right of it on the left edge). The block is left-aligned at the bulge's outer padding on the right
/// edge and mirrored, right-aligned, on the left edge (`BulgeTextFrame`), and centred in the blob at
/// rest (`PanelModel.bulgeTextPlacement`: on the slot, or moved with the flush blob at the first and
/// last slot); it never moves with the
/// goo spring. The lines fade in staggered (plain opacity): the name after `Theme.revealDelay`
/// (the bulge is about 60 % open), the status `Theme.revealStagger` later, the branch after that.
/// On collapse all fade out in `Theme.revealExitDuration`, before the bulge melts. The whole bulge
/// area is the click target (opens the session). Reduce Motion changes nothing here: it is fades already.
///
/// Line 1: a project dot (colour hashed from the project key), the name and, for an external session,
/// its tool as a small grey label (`parser  Codex`); the name is what truncates, never the tool. Line 2:
/// the status, with the activity while working, and the time in state. Line 3, when a branch is known:
/// `⎇ main` in grey. Three lines fit the 64 pt bulge (about 44 pt of text). The tool used to lead the
/// status line, where `Codex · Needs permission · 13h 25m` overflowed the bulge and lost the tool.
struct BulgeContentView: View {
    let row: SessionRow
    /// Texts shown (the hovered row, or every row in `.all` mode).
    let visible: Bool
    /// The status line ticks once a minute (only the shown row while expanded; the others never wake).
    let ticking: Bool
    /// Delay before the name appears (`PanelModel.revealDelay`, plus the `.all` mode row stagger).
    let revealDelay: TimeInterval
    /// How far the bulge reaches left of the capsule; the block's width.
    let reach: CGFloat
    /// Height of the blob the block is centred in (the row places it on the blob that is drawn).
    var height: CGFloat = GooLayout.bulgeHeight
    /// The panel's side: the text alignment mirrors on the left edge.
    var side: PanelSide = .default
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: side.bulgeTextAlignment, spacing: Theme.bulgeLineSpacing) {
                HStack(spacing: Theme.projectDotGap) {
                    Circle()
                        .fill(ProjectColor.color(for: row.projectKey).color)
                        .frame(width: Theme.projectDotSize, height: Theme.projectDotSize)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.bulgeToolGap) {
                        Text(row.name)
                            .font(Theme.bulgeNameFont)
                            .foregroundStyle(Theme.bulgeNameColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let tool = row.tool {
                            Text(Self.toolLabel(tool))
                                .font(Theme.bulgeToolFont)
                                .foregroundStyle(Theme.bulgeToolColor)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                .modifier(reveal(order: 0))
                StateDurationText(label: row.label, since: row.stateSince, ticking: ticking)
                    .font(Theme.bulgeStatusFont)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .modifier(reveal(order: 1))
                if let branch = row.gitBranch {
                    Text(Self.branchText(branch))
                        .font(Theme.branchFont)
                        .foregroundStyle(Theme.branchColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .modifier(reveal(order: 2))
                }
            }
            .modifier(BulgeTextFrame(side: side, reach: reach, height: height))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(reduceMotion: reduceMotion))
        .allowsHitTesting(visible)
    }

    /// The tool label after the name: the tool's display name, cut to `Theme.bulgeToolMaxCharacters`
    /// with an ellipsis, so a long custom `tool` from a session file still leaves room for the name.
    static func toolLabel(_ tool: String) -> String {
        guard tool.count > Theme.bulgeToolMaxCharacters else { return tool }
        return String(tool.prefix(Theme.bulgeToolMaxCharacters - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// `⎇ main`.
    static func branchText(_ branch: String) -> String {
        "\(Theme.branchGlyph) \(branch)"
    }

    /// The row's status colour: amber for needs input, cyan working, the your-turn lime, dimmed grey idle, mint finished, grey ended.
    private var statusColor: Color {
        switch row.status {
        case .needsInput: Theme.needsInputColor.color
        case .working: Theme.workingColor.color
        case .yourTurn: Theme.yourTurnColor.color
        case .idle: Theme.idleColor.color.opacity(Theme.bulgeIdleStatusOpacity)
        case .justFinished: Theme.justFinishedColor.color
        case .ended: Theme.endedColor.color
        }
    }

    private func reveal(order: Int) -> RevealModifier {
        RevealModifier(visible: visible, delay: revealDelay + Double(order) * Theme.revealStagger)
    }
}
