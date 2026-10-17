import QuartzCore

/// The magnification inputs of one face under Dock-style hover: a scale and a small offset toward
/// the pointer. `PanelModel` computes one per slot from the pointer's position (the playground from
/// the pointer over the hero row); the layer trees set it as a model transform and let Core Animation
/// ease to it. `.identity` is the rest state.
struct MagnifyState: Equatable, Sendable {
    var scale: CGFloat = 1
    /// Offset toward the pointer, in points, top-left coordinates (positive `dy` is down on screen).
    var dx: CGFloat = 0
    var dy: CGFloat = 0

    static let identity = MagnifyState()

    /// The Gaussian falloff of the magnification at `distance` from the pointer, in [0, 1].
    static func weight(distance: CGFloat, spread: CGFloat = Theme.magnifySpread) -> CGFloat {
        guard spread > 0 else { return distance == 0 ? 1 : 0 }
        let ratio = distance / spread
        return exp(-ratio * ratio)
    }

    /// The scale at `distance` from the pointer, before the clamp.
    static func scale(distance: CGFloat, spread: CGFloat = Theme.magnifySpread) -> CGFloat {
        1 + (Theme.magnifyMax - 1) * weight(distance: distance, spread: spread)
    }

    /// The largest magnification of a face of `faceSize` whose rest scale is `restScale` (a waiting
    /// face is bigger already) that still fits the capsule width with `Theme.magnifyMargin` to spare.
    static func maxScale(faceSize: CGFloat, restScale: CGFloat = 1) -> CGFloat {
        (Theme.capsuleWidth - Theme.magnifyMargin) / (faceSize * restScale)
    }

    /// The magnification of a face whose centre is `offset` away from the pointer (pointer minus
    /// centre, top-left coordinates).
    /// - Parameters:
    ///   - distance: the distance that drives the falloff (along the column in the panel, along the row in the playground).
    ///   - spread: width of the falloff.
    ///   - faceSize: side of the face; the follow amounts scale with it.
    ///   - followReach: the offset at which the follow reaches its full amount in each direction.
    ///   - maxScale: clamp for the scale.
    static func at(
        offset: CGPoint, distance: CGFloat, spread: CGFloat = Theme.magnifySpread, faceSize: CGFloat = Theme.faceSize,
        followReach: CGSize = CGSize(width: Theme.faceSize / 2, height: Theme.rowPitch / 2), maxScale: CGFloat = .infinity
    ) -> MagnifyState {
        let weight = weight(distance: distance, spread: spread)
        let scale = min(1 + (Theme.magnifyMax - 1) * weight, max(maxScale, 1))
        let sizeFactor = faceSize / Theme.faceSize
        let towardX = followReach.width > 0 ? min(max(offset.x / followReach.width, -1), 1) : 0
        let towardY = followReach.height > 0 ? min(max(offset.y / followReach.height, -1), 1) : 0
        return MagnifyState(
            scale: scale,
            dx: Theme.followX * sizeFactor * weight * towardX,
            dy: Theme.followY * sizeFactor * weight * towardY
        )
    }

    /// The layer transform: scale about the centre, then the offset. The layers are not flipped
    /// (y up), so the top-left `dy` turns negative.
    var transform: CATransform3D {
        CATransform3DScale(CATransform3DMakeTranslation(dx, -dy, 0), scale, scale, 1)
    }
}
