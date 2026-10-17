import Foundation

/// Where both eyes look, as a shift of the whole eye pair in fractions of the face size.
/// Negative x looks left (toward the screen, since the panel sits on the right edge; on the left edge the
/// face is drawn mirrored, `PanelSide.faceTransform`, so it looks right); positive y looks up.
struct GazeOffset: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0

    static let centre = GazeOffset()
}
