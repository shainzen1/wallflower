import CoreGraphics
import Foundation

/// The "!" the eyes turn into for needs input: each eye's shape is driven to a tall narrow
/// rounded bar (the regular eye path with bar parameters, so the path structure stays constant
/// and the pose springs like any other), and a round dot sits below it on its own layer.
/// All values are fractions of the face size, from `Theme`.
enum ExclamationPose {
    /// The bar, as eye parameters: narrow, tall, fully rounded ends, raised so the whole "!" is centred.
    static let bar = EyeParameters(
        offsetX: 0, offsetY: -Theme.exclamationBarRaise,
        width: Theme.exclamationBarWidth, height: Theme.exclamationBarHeight,
        topSlope: 0, bottomSlope: 0,
        topRadius: 1, bottomRadius: 1,
        topInverseRadius: 0, topInverseOffset: 0, bottomInverseRadius: 0, bottomInverseOffset: 0
    )

    /// Both eyes as bars. No identity preset is applied: a "!" is typographic, not a face shape.
    static let pose = FacePose(both: bar)

    /// Centre of the dot below the bar in local eye coordinates (+y down), fraction of the face size.
    static var dotCentreYDown: Double {
        -Theme.exclamationBarRaise + Theme.exclamationBarHeight / 2 + Theme.exclamationDotGap + Theme.exclamationDotDiameter / 2
    }

    /// Bounding rect of the dot in layer coordinates (+y up) of a square face of `faceSize`.
    static func dotRect(faceSize: CGFloat, mirrored: Bool) -> CGRect {
        let s = Double(faceSize)
        let sx: Double = mirrored ? -1 : 1
        let centreX = s / 2 - sx * (Theme.eyeSpacing * s / 2)
        let centreY = s / 2 + Theme.eyeVerticalOffset * s - dotCentreYDown * s
        let d = Theme.exclamationDotDiameter * s
        return CGRect(x: centreX - d / 2, y: centreY - d / 2, width: d, height: d)
    }

    /// The dot's path in its own layer's bounds (origin zero), so the layer can scale about its centre.
    static func dotPath(faceSize: CGFloat) -> CGPath {
        let d = Theme.exclamationDotDiameter * Double(faceSize)
        return CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)
    }
}
