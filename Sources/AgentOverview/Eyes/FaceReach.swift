import CoreGraphics
import Foundation

/// How far a face's body reaches above and below its centre at magnification 1, in points, at the
/// peak of everything that scales it: the rest scale (a waiting face is bigger), the grow, the pulse
/// or breath and the finished bounce, and of the your-turn swap (the larger silhouette) and its hop. `MagnifyColumn` shares the room between neighbouring faces with
/// it, so no two bodies come closer than `Theme.rowBodyGap` under magnification.
///
/// Mirrors what `BlobProgramBuilder` gives each status (a test keeps the two in step), without
/// building a program on every pointer move.
struct FaceReach: Equatable, Sendable {
    var up: CGFloat
    var down: CGFloat
    /// The rest scale the clamp against the capsule width uses (`MagnifyState.maxScale`): the attention
    /// scale times the grow for a waiting face, 1 while the hover has taken the attention scale over.
    var boxScale: CGFloat = 1

    /// The reach of a silhouette as fractions of the face size, from the drawn path's bounding box
    /// (the curve between the samples, not just the samples). Computed once per shape.
    static func extent(of shape: BlobShape) -> (up: Double, down: Double) {
        extents[shape] ?? (Theme.blobRadius, Theme.blobRadius)
    }

    private static let extents: [BlobShape: (up: Double, down: Double)] = {
        var table: [BlobShape: (up: Double, down: Double)] = [:]
        for shape in BlobShape.allCases {
            // Layer coordinates, y up: the top of the silhouette is the box's maxY.
            let box = shape.profile.path(size: 1).boundingBoxOfPath
            table[shape] = (Double(box.maxY) - 0.5, 0.5 - Double(box.minY))
        }
        return table
    }()

    /// The reach of a blob of `shape` on a face of `faceSize` at `peakScale`.
    static func blob(_ shape: BlobShape, faceSize: CGFloat, peakScale: Double, boxScale: Double = 1) -> FaceReach {
        let extent = extent(of: shape)
        return FaceReach(
            up: CGFloat(extent.up * peakScale) * faceSize,
            down: CGFloat(extent.down * peakScale) * faceSize,
            boxScale: CGFloat(boxScale)
        )
    }

    /// Peak scale of a body: the rest scale plus the amplitudes of the additive loops on the scaler
    /// (`transform.scale` loops add; `BlobLayerTree.restTransform` keeps z in step so they add to the rest scale).
    static func peakScale(restScale: Double, grow: AttentionGrow?, bodyLoop: BreathLoop?) -> Double {
        restScale + (grow.map { $0.scale - 1 } ?? 0) + (bodyLoop.map { $0.scale - 1 } ?? 0)
    }

    /// A session face showing `status`. `hovered`: the row is hovered under the magnify effect, so a
    /// waiting face rests at 1 with its grow paused (the pulse keeps going).
    static func session(
        status: FaceStatus, seed: String, hovered: Bool, faceSize: CGFloat = Theme.faceSize,
        style: FaceStyle = Theme.faceStyle, shapeMode: Theme.BlobShapeMode = Theme.blobShapeMode
    ) -> FaceReach {
        if style == .dotMatrix { return disc(faceSize: faceSize) }
        let shape = shapeMode == .status ? BlobBody.forStatus(status).shape : FaceIdentity(seed: seed).shape
        switch status {
        case .needsInput(let kind):
            let pulse = kind == .permission ? Theme.permissionPulse : Theme.blobNeedsInputPulse
            if hovered {
                return blob(shape, faceSize: faceSize, peakScale: peakScale(restScale: 1, grow: nil, bodyLoop: pulse))
            }
            let grow = BlobProgramBuilder.attentionGrow(for: kind)
            return blob(
                shape, faceSize: faceSize, peakScale: peakScale(restScale: Theme.attentionScale, grow: grow, bodyLoop: pulse),
                boxScale: Theme.attentionScale * grow.scale
            )
        case .working:
            return blob(shape, faceSize: faceSize, peakScale: peakScale(restScale: 1, grow: nil, bodyLoop: Theme.blobWorkingBreath))
        case .justFinished:
            return blob(shape, faceSize: faceSize, peakScale: Theme.blobBounceScale)
        case .yourTurn:
            // Hovered, the swap and the hop rest on the first silhouette.
            if hovered { return blob(shape, faceSize: faceSize, peakScale: 1) }
            return yourTurn(shapes: shapeMode == .status ? [Theme.yourTurnShapes.0, Theme.yourTurnShapes.1] : [shape], faceSize: faceSize)
        case .idle, .ended:
            return blob(shape, faceSize: faceSize, peakScale: 1)
        }
    }

    /// A your-turn face: the farther reach of the silhouettes it swaps between, plus the hop above.
    static func yourTurn(shapes: [BlobShape], faceSize: CGFloat) -> FaceReach {
        let extents = shapes.map(extent(of:))
        let up = extents.map(\.up).max() ?? Theme.blobRadius
        let down = extents.map(\.down).max() ?? Theme.blobRadius
        return FaceReach(up: CGFloat(up + Theme.yourTurnBounceHeight) * faceSize, down: CGFloat(down) * faceSize)
    }

    /// An action face: its own silhouette at rest and hovered, the working cloud (with its breath) while launching.
    static func action(_ face: ActionFace, faceSize: CGFloat = Theme.faceSize, style: FaceStyle = Theme.faceStyle) -> FaceReach {
        if style == .dotMatrix { return disc(faceSize: faceSize) }
        if face.phase == .launching {
            return blob(Theme.blobWorkingShape, faceSize: faceSize, peakScale: peakScale(restScale: 1, grow: nil, bodyLoop: Theme.blobWorkingBreath))
        }
        return blob(face.shape, faceSize: faceSize, peakScale: 1)
    }

    /// The new session button: its ring, `Theme.newSessionSize` across, no loops. It never magnifies
    /// (a fixed face in `MagnifyColumn`); the reach is the body its neighbours keep the gap to.
    static func newSession(faceSize: CGFloat = Theme.faceSize, size: CGFloat = Theme.newSessionSize) -> FaceReach {
        FaceReach(up: size / 2, down: size / 2, boxScale: size / faceSize)
    }

    /// The dot-matrix face: the round disc fills the face square.
    static func disc(faceSize: CGFloat) -> FaceReach {
        FaceReach(up: faceSize / 2, down: faceSize / 2)
    }
}
