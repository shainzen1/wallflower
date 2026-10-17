import SwiftUI

/// The new session button at the top of the column: the same geometry as `ActionRowView` (the glyph
/// at the screen edge, the bulge content beside it, `EdgeRow`), in a `Theme.newSessionPitch` slot.
/// The glyph is symmetric, so it is the same on both sides. It is
/// always there: no arrival, no departure, and it cannot be thrown (a press on it still drags the
/// panel along the edge). Bulge: "New session", then where it opens (Claude app or Terminal). The ring
/// is never magnified; it reads no pointer, so a pointer move re-evaluates nothing here.
struct NewSessionRowView: View {
    let model: PanelModel
    /// "New session" and the route shown in the bulge.
    let expanded: Bool
    /// The button is under the pointer: the ring brightens and the plus turns.
    let hovered: Bool
    let revealDelay: TimeInterval
    let bulgeReach: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        let bulge = model.bulgeTextPlacement(slot: PanelModel.newSessionSlot)
        EdgeRow(side: model.side) {
            ActionBulgeView(
                title: Theme.newSessionTitle,
                detail: model.newSessionRoute.title,
                visible: expanded,
                revealDelay: revealDelay,
                reach: bulgeReach,
                height: bulge.height,
                side: model.side,
                reduceMotion: reduceMotion,
                action: action
            )
            .offset(y: bulge.offset)
            .frame(width: bulgeReach, height: Theme.faceSize)
        } face: {
            Button(action: action) {
                NewSessionGlyphView(state: NewSessionGlyphState(
                    hovered: hovered,
                    clickToken: model.newSessionClickToken,
                    reduceMotion: reduceMotion
                ))
                .frame(width: Theme.faceSize, height: Theme.faceSize)
            }
            .buttonStyle(RowPressStyle(reduceMotion: reduceMotion))
            .frame(width: Theme.capsuleWidth, height: Theme.faceSize)
        }
        .zIndex(hovered ? 2 : 0)
    }
}
