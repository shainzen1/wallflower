import Foundation

/// The soft glow behind a blob face, shaped like the body: the body's silhouette at its rest scale,
/// scaled up by `Theme.haloScale` around the centre (held at `fillCap` where that would reach too
/// far), filled with `color` and softened at the rim by a Gaussian of `Theme.haloSoftness`. The glow
/// morphs with the body (the your-turn swap, a status change) and never magnifies, so it stays in its
/// row: its softened rim is spent by `Theme.haloOuterRadius`, swell included. Its opacity rests at
/// `restFraction` of `opacity` and rises either with the attention grow (`grow`: the same keyframes and
/// phase as the body's grow loop) or on a breath (`breath`: a sine-like swing, `scale` is the low
/// fraction). Nothing pulses under Reduce Motion: the glow rests steady at `restFraction`.
struct BlobHalo: Equatable, Sendable {
    var color: EyeColor
    var opacity: Double
    var restFraction: Double
    var grow: AttentionGrow? = nil
    var breath: BreathLoop? = nil

    /// The amber halo of a waiting face, pulsing with its grow.
    static func attention(grow: AttentionGrow) -> BlobHalo {
        BlobHalo(color: Theme.needsInputColor, opacity: Theme.attentionHaloOpacity, restFraction: Theme.attentionHaloRestFraction, grow: grow)
    }

    /// The mint halo of a face that just finished, breathing.
    static let done = BlobHalo(color: Theme.justFinishedColor, opacity: Theme.doneHaloOpacity, restFraction: Theme.doneHaloPulse.scale, breath: Theme.doneHaloPulse)

    /// The halo of a face whose turn ended (waiting for the next instruction): the body's colour,
    /// `Theme.yourTurnColor` in every colour mode, at `Theme.yourTurnHaloOpacity` (louder than the done
    /// halo, below the amber one), on the done halo's breath.
    static func yourTurn(color: EyeColor) -> BlobHalo {
        BlobHalo(color: color, opacity: Theme.yourTurnHaloOpacity, restFraction: Theme.yourTurnHaloPulse.scale, breath: Theme.yourTurnHaloPulse)
    }

    /// The same halo at peak opacity 1: the face's halo layer loops on these relative levels while
    /// its host carries `opacity`, so a change of opacity (done to your turn) eases on the host and
    /// leaves a running breath alone.
    var unit: BlobHalo {
        var unit = self
        unit.opacity = 1
        return unit
    }

    // MARK: Shape

    /// The outermost extent of the glow as a fraction of the face size (`Theme.haloOuterRadius`).
    static var outerRadius: Double { Double(Theme.haloOuterRadius / Theme.faceSize) }

    /// How far the softened rim reaches beyond the fill's edge before it is spent, as a fraction of
    /// the face size.
    static var tail: Double { Theme.haloSoftness * Theme.haloTailSigmas }

    /// The largest radius the fill may have (fraction of the face size): the swollen glow's tail ends
    /// at the outer radius.
    static var fillCap: Double { outerRadius / Theme.haloHopSwell - tail }

    /// The glow's silhouette for `body` shown at `restScale`: every radius scaled by `Theme.haloScale`
    /// and held at `fillCap`. The same sample angles as the body, so the glow morphs with it.
    static func profile(for body: BlobBody, restScale: Double) -> BlobProfile {
        BlobProfile(radii: body.profile.radii.map { min($0 * restScale * Theme.haloScale, fillCap) })
    }

    /// The farthest the glow ever reaches from the centre (fraction of the face size): the fill's
    /// largest radius plus the tail, at the top of the hop swell.
    static func extent(of profile: BlobProfile) -> Double {
        ((profile.radii.max() ?? 0) + tail) * Theme.haloHopSwell
    }
}
