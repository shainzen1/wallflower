import Foundation

/// A complete pose of the face: both eyes, where they look, and an optional colour override.
struct FacePose: Equatable, Sendable {
    var left: EyeParameters
    var right: EyeParameters
    var gaze: GazeOffset = .centre
    /// When set, the eyes take this colour instead of the identity colour (amber for needs input).
    var colorOverride: EyeColor? = nil

    /// A symmetric pose: both eyes share the same parameters (the right eye is mirrored by the path builder).
    init(both eye: EyeParameters, gaze: GazeOffset = .centre, colorOverride: EyeColor? = nil) {
        self.left = eye
        self.right = eye
        self.gaze = gaze
        self.colorOverride = colorOverride
    }

    /// An asymmetric pose.
    init(left: EyeParameters, right: EyeParameters, gaze: GazeOffset = .centre, colorOverride: EyeColor? = nil) {
        self.left = left
        self.right = right
        self.gaze = gaze
        self.colorOverride = colorOverride
    }

    /// Linear blend of two poses (eyes and gaze; the colour override switches at the midpoint).
    static func lerp(_ a: FacePose, _ b: FacePose, t: Double) -> FacePose {
        FacePose(
            left: EyeParameters.lerp(a.left, b.left, t: t),
            right: EyeParameters.lerp(a.right, b.right, t: t),
            gaze: GazeOffset(x: a.gaze.x + (b.gaze.x - a.gaze.x) * t, y: a.gaze.y + (b.gaze.y - a.gaze.y) * t),
            colorOverride: t < 0.5 ? a.colorOverride : b.colorOverride
        )
    }

    /// The pose with a preset delta added to both eyes.
    func applying(_ preset: EyePreset) -> FacePose {
        var p = self
        p.left = left.adding(preset.delta)
        p.right = right.adding(preset.delta)
        return p
    }

    /// The pose with both eyes closed to a line (blink, ended).
    func closed() -> FacePose {
        var p = self
        p.left = left.closed()
        p.right = right.closed()
        return p
    }

    /// The same pose looking somewhere else.
    func looking(_ gaze: GazeOffset) -> FacePose {
        var p = self
        p.gaze = gaze
        return p
    }

    /// The same pose in another colour.
    func tinted(_ color: EyeColor?) -> FacePose {
        var p = self
        p.colorOverride = color
        return p
    }
}
