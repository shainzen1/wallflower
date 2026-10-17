import Foundation

/// Everything the blob layer tree needs to show one face in one state: the resting eye pose,
/// the body (silhouette and squash), the body colour, the eye tracks to install and the body
/// loops. Built by `BlobProgramBuilder` from a mode and an identity.
struct BlobProgram: Equatable, Sendable {
    var pose: BlobEyePose
    var body: BlobBody
    /// Body colour at rest.
    var color: EyeColor
    /// Shown first instead of `color`, then eased to `color` after `Theme.doneHold` (the mint flash).
    var flashColor: EyeColor? = nil
    /// Eye path loops and scheduled moves, installed in order.
    var tracks: [BlobTrack] = []
    /// Body scale loop (needs input pulse, working breath).
    var bodyLoop: BreathLoop? = nil
    /// Periodic grow of the body while waiting for the person (next to the pulse).
    var grow: AttentionGrow? = nil
    /// One soft scale bounce on arrival (just finished).
    var bounce = false
    /// A later body change (the sleepy sag).
    var scheduledBody: BlobScheduledBody? = nil
    /// Opacity pulse of the eye pair (running commands).
    var eyePulse: BlobEyePulse? = nil
    /// Soft glow behind the face (waiting: amber with the grow; just finished: mint, breathing).
    var halo: BlobHalo? = nil
    /// Scale of the body at rest (a waiting face is a notch bigger); loops add to it.
    var restScale: Double = 1
    /// One-shot burst of dots flying outward on arrival (just finished).
    var burst = false
    /// The your-turn loop: the body swaps silhouettes and hops with each swap.
    var swap: BlobShapeSwap? = nil
    /// Plays the excited reaction (eyes widen, a double hop and wiggle, a brighter body) when the
    /// face's excited token changes: the working face, whose session just took the person's message.
    var excited = false
}
