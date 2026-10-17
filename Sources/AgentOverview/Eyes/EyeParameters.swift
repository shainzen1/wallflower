import Foundation

/// The shape of one eye. Every value is a fraction of the face size (so a 40 pt and a 120 pt
/// face use the same numbers), and the struct is linearly interpolable so poses can be blended.
///
/// Coordinates are "local eye" coordinates: +x points toward the inner side (the nose),
/// +y points down. The right eye is the mirror image, so the same parameters describe a
/// symmetric pair; asymmetric expressions give the two eyes different values.
struct EyeParameters: Equatable, Sendable {
    /// Shift of the eye centre toward the nose (positive) or away from it.
    var offsetX: Double = 0
    /// Shift of the eye centre downward (positive) or upward.
    var offsetY: Double = 0
    /// Width of the eye block.
    var width: Double = 0.24
    /// Height of the eye block.
    var height: Double = 0.30
    /// Tilt of the top edge about its midpoint. Positive lowers the inner corner (angry brows).
    var topSlope: Double = 0
    /// Tilt of the bottom edge about its midpoint. Positive raises the inner corner.
    var bottomSlope: Double = 0
    /// Rounding of the two top corners, 0 (sharp) to 1 (as round as the block allows).
    var topRadius: Double = 0.7
    /// Rounding of the two bottom corners, 0 to 1.
    var bottomRadius: Double = 0.7
    /// Half width of the concave arc cut into the top edge, as a fraction of the eye half width (0 = no cut, 1 = full edge).
    var topInverseRadius: Double = 0
    /// Depth of that top cut, as a fraction of the eye height (0 = flat edge).
    var topInverseOffset: Double = 0
    /// Half width of the concave arc cut into the bottom edge, 0 to 1.
    var bottomInverseRadius: Double = 0
    /// Depth of the bottom cut, as a fraction of the eye height. A wide, deep bottom cut makes a smile.
    var bottomInverseOffset: Double = 0

    /// Linear blend between two parameter sets; `t` 0 gives `a`, 1 gives `b`.
    static func lerp(_ a: EyeParameters, _ b: EyeParameters, t: Double) -> EyeParameters {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return EyeParameters(
            offsetX: mix(a.offsetX, b.offsetX),
            offsetY: mix(a.offsetY, b.offsetY),
            width: mix(a.width, b.width),
            height: mix(a.height, b.height),
            topSlope: mix(a.topSlope, b.topSlope),
            bottomSlope: mix(a.bottomSlope, b.bottomSlope),
            topRadius: mix(a.topRadius, b.topRadius),
            bottomRadius: mix(a.bottomRadius, b.bottomRadius),
            topInverseRadius: mix(a.topInverseRadius, b.topInverseRadius),
            topInverseOffset: mix(a.topInverseOffset, b.topInverseOffset),
            bottomInverseRadius: mix(a.bottomInverseRadius, b.bottomInverseRadius),
            bottomInverseOffset: mix(a.bottomInverseOffset, b.bottomInverseOffset)
        )
    }

    /// Component-wise sum, used to apply a preset delta on top of an expression.
    func adding(_ delta: EyeParameters) -> EyeParameters {
        EyeParameters(
            offsetX: offsetX + delta.offsetX,
            offsetY: offsetY + delta.offsetY,
            width: width + delta.width,
            height: height + delta.height,
            topSlope: topSlope + delta.topSlope,
            bottomSlope: bottomSlope + delta.bottomSlope,
            topRadius: topRadius + delta.topRadius,
            bottomRadius: bottomRadius + delta.bottomRadius,
            topInverseRadius: topInverseRadius + delta.topInverseRadius,
            topInverseOffset: topInverseOffset + delta.topInverseOffset,
            bottomInverseRadius: bottomInverseRadius + delta.bottomInverseRadius,
            bottomInverseOffset: bottomInverseOffset + delta.bottomInverseOffset
        )
    }

    /// The same eye closed to a thin line: the height collapses, the cuts vanish, the ends go round.
    /// Slopes and width stay, so a closed angry eye still tilts like an angry eye.
    func closed() -> EyeParameters {
        var c = self
        c.height = Theme.closedEyeHeight
        c.topInverseOffset = 0
        c.bottomInverseOffset = 0
        c.topInverseRadius = 0
        c.bottomInverseRadius = 0
        c.topRadius = 1
        c.bottomRadius = 1
        return c
    }

    /// A zero delta: adding it changes nothing.
    static let zero = EyeParameters(
        offsetX: 0, offsetY: 0, width: 0, height: 0, topSlope: 0, bottomSlope: 0,
        topRadius: 0, bottomRadius: 0, topInverseRadius: 0, topInverseOffset: 0,
        bottomInverseRadius: 0, bottomInverseOffset: 0
    )
}
