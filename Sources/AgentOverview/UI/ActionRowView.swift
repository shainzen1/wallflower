import SwiftUI

/// One action row below the divider: the same geometry as `SessionRowView` (face at the screen
/// edge, bulge content beside it, `EdgeRow`), with the action face: resting eyes, open on hover, a
/// squint and the working cloud after a click.
struct ActionRowView: View {
    let model: PanelModel
    let row: ActionRow
    /// Slot index of the row (session rows first, then the actions), for the magnification.
    let slot: Int
    /// Name and prompt shown in the bulge, eyes open.
    let expanded: Bool
    let revealDelay: TimeInterval
    let bulgeReach: CGFloat
    let reduceMotion: Bool
    /// The row is under the pointer: under the `.stretch` effect the face stretches toward the bulge (the genie).
    var hovered = false
    /// Seconds before the face pops in when the row first appears (`RowEntrance.faceDelay`).
    var enterDelay: TimeInterval = 0
    let action: () -> Void

    var body: some View {
        let bulge = model.bulgeTextPlacement(slot: slot)
        EdgeRow(side: model.side) {
            ActionBulgeView(
                row: row,
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
                MagnifiedFaceView(
                    model: model,
                    slot: slot,
                    face: FaceView(seed: row.seed, action: row.face(hovered: expanded))
                        .squint(token: row.squintToken)
                        .hovered(hovered)
                        .entrance(delay: enterDelay)
                        .side(model.side)
                )
            }
            .buttonStyle(RowPressStyle(reduceMotion: reduceMotion))
            .frame(width: Theme.capsuleWidth, height: Theme.faceSize)
        }
        // The hovered row draws above everything (an action face never needs attention).
        .zIndex(hovered ? 2 : 0)
    }
}
