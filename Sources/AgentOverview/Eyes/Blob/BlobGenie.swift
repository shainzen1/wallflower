import Foundation

/// The genie stretch of a hovered blob: the silhouette reaches leftward, toward the pointer and
/// the bulge, with a taper. Every radius is scaled by `1 + Theme.genieStretch * smoothstep(cos
/// of the angle toward the left)^2`: the full stretch at the leftmost sample, nothing from the top
/// and bottom round to the right, and the square keeps the stretch close to the tip so it reads as
/// a tail, not a wider oval. The sample angles never change, so the stretched path keeps the
/// element count and Core Animation can spring between the two. On the left screen edge the whole
/// face is drawn mirrored (`PanelSide.faceTransform`), so the same stretch reaches rightward there.
enum BlobGenie {
    /// The profile stretched toward the left.
    static func stretched(_ profile: BlobProfile) -> BlobProfile {
        BlobProfile(radii: profile.radii.enumerated().map { index, radius in
            radius * (1 + Theme.genieStretch * weight(at: BlobProfile.angle(index)))
        })
    }

    /// How much of the stretch applies at `angle` (0 = right, pi = left), in [0, 1].
    static func weight(at angle: Double) -> Double {
        let toward = min(max(-cos(angle), 0), 1)
        let smooth = toward * toward * (3 - 2 * toward)
        return smooth * smooth
    }
}
