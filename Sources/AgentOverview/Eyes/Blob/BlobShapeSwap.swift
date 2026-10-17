import Foundation

/// The your-turn loop of a blob face: the body holds its silhouette for `hold`, morphs to `alternate`
/// in `duration` (ease-in-out), holds that, morphs back, and hops by `bounceHeight` of the face size
/// with every swap (a tiny squash on landing). Without an `alternate` (`.identity` shape mode, or a
/// forced body) only the hop plays, on the same beat. One period is two swaps; the layer tree starts
/// it after a seeded fraction of a period, so two faces never swap in step. Nothing loops under
/// Reduce Motion, and a hovered face pauses it.
struct BlobShapeSwap: Equatable, Sendable {
    var alternate: BlobBody?
    var hold: TimeInterval = Theme.yourTurnSwapHold
    var duration: TimeInterval = Theme.yourTurnSwapDuration
    var bounceHeight: Double = Theme.yourTurnBounceHeight

    /// One full cycle: there and back, each a morph and a hold.
    var period: TimeInterval { 2 * (hold + duration) }

    /// When each swap (and its hop) starts within a period.
    var swapTimes: [TimeInterval] { [0, hold + duration] }
}
