import Foundation

/// Everything the layer tree needs to show one face in one state: the resolved base pose
/// (preset applied, gaze and colour set), the path tracks to install, and which transform
/// and glow loops run. Built by `FaceProgramBuilder` from a mode and an identity.
struct FaceProgram: Equatable, Sendable {
    /// Resolved pose, preset already applied.
    var pose: FacePose
    /// Colour of the eyes and the glow (the resting colour of the state).
    var color: EyeColor
    /// Glow strength at rest (idle faces glow dimmer so they recede).
    var glow: Float = Theme.glowOpacity
    /// Shown first instead of `color`, then eased to `color` after `Theme.justFinishedHold` (the mint flash).
    var flashColor: EyeColor? = nil
    /// The eyes are exclamation marks: the dots below the bars are visible.
    var exclamation = false
    /// Path loops and scheduled moves, installed in order.
    var tracks: [PathTrack] = []
    /// Glance left and right while working.
    var dart = false
    /// Slow vertical "reading" scan while working.
    var scan = false
    /// Slow drifting gaze wander while idle.
    var wander = false
    /// Scale breath of the eye pair (thinking while working, breathing while idle).
    var breath: BreathLoop? = nil
    /// Slow glow pulse for needs input.
    var pulse = false
    /// Periodic grow of the eye pair while waiting for the person (next to the pulse).
    var grow: AttentionGrow? = nil
    /// One scale bounce on arrival (just finished).
    var bounce = false
}
