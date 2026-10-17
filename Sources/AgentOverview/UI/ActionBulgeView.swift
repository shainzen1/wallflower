import SwiftUI

/// The two-line bulge content of an action row and of the new session button: a title on line 1, a
/// detail in grey on line 2. For an action: its name and its prompt (or, for a while after a click
/// that could only prefill it, `Theme.actionSendHint` in amber). For the new session button: "New
/// session" and where it opens. No dot, no time. Same reveal timing and click target as `BulgeContentView`.
struct ActionBulgeView: View {
    let title: String
    let detail: String
    let detailColor: Color
    let visible: Bool
    let revealDelay: TimeInterval
    let reach: CGFloat
    /// Height of the blob the block is centred in.
    let height: CGFloat
    /// The panel's side: the text alignment mirrors on the left edge (`BulgeTextFrame`).
    let side: PanelSide
    let reduceMotion: Bool
    let action: () -> Void

    /// An action row's bulge: name, then the prompt or the send hint.
    init(
        row: ActionRow, visible: Bool, revealDelay: TimeInterval, reach: CGFloat, height: CGFloat = GooLayout.bulgeHeight,
        side: PanelSide = .default, reduceMotion: Bool, action: @escaping () -> Void
    ) {
        self.init(
            title: row.name, detail: row.hint ?? row.prompt,
            detailColor: row.hint == nil ? Theme.actionPromptColor : Theme.actionSendHintColor,
            visible: visible, revealDelay: revealDelay, reach: reach, height: height, side: side, reduceMotion: reduceMotion, action: action
        )
    }

    init(
        title: String, detail: String, detailColor: Color = Theme.actionPromptColor, visible: Bool, revealDelay: TimeInterval,
        reach: CGFloat, height: CGFloat = GooLayout.bulgeHeight, side: PanelSide = .default, reduceMotion: Bool, action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.detailColor = detailColor
        self.visible = visible
        self.revealDelay = revealDelay
        self.reach = reach
        self.height = height
        self.side = side
        self.reduceMotion = reduceMotion
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: side.bulgeTextAlignment, spacing: Theme.bulgeLineSpacing) {
                Text(title)
                    .font(Theme.bulgeNameFont)
                    .foregroundStyle(Theme.bulgeNameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .modifier(reveal(order: 0))
                Text(detail)
                    .font(Theme.actionPromptFont)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .modifier(reveal(order: 1))
            }
            .modifier(BulgeTextFrame(side: side, reach: reach, height: height))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(reduceMotion: reduceMotion))
        .allowsHitTesting(visible)
    }

    private func reveal(order: Int) -> RevealModifier {
        RevealModifier(visible: visible, delay: revealDelay + Double(order) * Theme.revealStagger)
    }
}
