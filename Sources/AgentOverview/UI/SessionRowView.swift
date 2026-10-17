import SwiftUI

/// One row of the capsule. The face sits at a fixed position at the screen edge (centred in the
/// capsule's width); the bulge content (name and status) grows away from the edge beside it, leftward
/// on the right edge and rightward on the left (`EdgeRow`). The row is `Theme.faceSize` tall for the
/// stack; the bulge content overflows that height by `Theme.bulgePadding` on each side, moved
/// with the flush blob at the first and last slot (`PanelModel.bulgeTextPlacement`).
/// The face gets the row's activity, subagent count, attention and excited tokens, hover and magnification;
/// every status the row shows is reported to `onStatusChange` (the model decides whether that earns a
/// hop or the excited reaction).
struct SessionRowView: View {
    let model: PanelModel
    let row: SessionRow
    /// Slot index of the row (for the magnification).
    let slot: Int
    /// Name and status shown in the bulge.
    let expanded: Bool
    /// The time-in-state text ticks (only while expanded, only the shown row).
    let ticking: Bool
    /// Delay before the name appears in the bulge.
    let revealDelay: TimeInterval
    /// How far the bulge reaches left of the capsule.
    let bulgeReach: CGFloat
    let reduceMotion: Bool
    /// Bumped by the model when the session enters needs input; the face hops once.
    var attentionToken = 0
    /// Bumped by the model when a resting or waiting session starts working; the face perks up once.
    var excitedToken = 0
    /// The row is under the pointer: under the `.stretch` effect the face stretches toward the bulge (the genie).
    var hovered = false
    /// The face is held, springing back or flying away (a throw): it draws on top of everything.
    var lifted = false
    /// Seconds before the face pops in when the row first appears (`RowEntrance.faceDelay`).
    var enterDelay: TimeInterval = 0
    var onStatusChange: (FaceStatus) -> Void = { _ in }
    let action: () -> Void

    /// Waiting, just finished or your turn: the face carries a halo and draws above its idle neighbours.
    private var needsAttention: Bool {
        row.status.isNeedsInput || row.status == .justFinished || row.status.isYourTurn
    }

    var body: some View {
        let bulge = model.bulgeTextPlacement(slot: slot)
        EdgeRow(side: model.side) {
            BulgeContentView(
                row: row,
                visible: expanded,
                ticking: ticking,
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
                    key: row.key,
                    face: FaceView(seed: row.seed, status: row.status)
                        .project(row.projectKey)
                        .activity(row.activity)
                        .satellites(row.subagentCount)
                        .attention(token: attentionToken)
                        .excited(token: excitedToken)
                        .hovered(hovered)
                        .entrance(delay: enterDelay)
                        .side(model.side)
                )
            }
            .buttonStyle(RowPressStyle(reduceMotion: reduceMotion))
            .scaleEffect(row.ended && !reduceMotion ? Theme.endedFaceScale : 1)
            .frame(width: Theme.capsuleWidth, height: Theme.faceSize)
        }
        // A held or thrown face draws above everything, then the hovered row, then a waiting, just
        // finished or your-turn one above idle neighbours.
        .zIndex(lifted ? Theme.throwZIndex : hovered ? 2 : (needsAttention ? 1 : 0))
        .opacity(row.ended ? Theme.endedRowOpacity : 1)
        .animation(Theme.closeSpring, value: row.ended)
        .onChange(of: row.status, initial: true) { _, status in
            onStatusChange(status)
        }
    }
}
