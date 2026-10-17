import Foundation

/// The look of an action face: its phase plus the silhouette and body colour, which an entry in
/// `actions.json` may override (`Theme.actionShape`, `Theme.actionColor` otherwise).
struct ActionFace: Equatable, Sendable {
    var phase: ActionFacePhase
    var shape: BlobShape = Theme.actionShape
    var color: EyeColor = Theme.actionColor
}
