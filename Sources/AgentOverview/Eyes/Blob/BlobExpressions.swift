import Foundation

/// The blob eye pose per expression, as plain literals tuned by eye. Everything is done with
/// eye size, tilt, spacing, lift and head gaze: no brows, no mouth.
///
/// Reading the values: tilt positive leans the tops outward (\ /), which with a big angle reads
/// as a V brow (angry); negative leans them inward (/ \), the sad or worried look. Lower, wider
/// eyes squint; tall narrow ones stare. Yaw negative looks left (toward the screen; mirrored with the face on the left edge).
enum BlobExpressions {
    static func pose(for expression: Expression) -> BlobEyePose {
        switch expression {
        case .normal:
            return BlobEyePose()

        case .happy:
            return BlobEyePose(both: BlobEye(width: 0.135, height: 0.21, tilt: 27), split: 51, lift: 0.035)

        case .glee:
            return BlobEyePose(both: BlobEye(width: 0.145, height: 0.15, tilt: 31), split: 54, lift: 0.045)

        case .sad:
            return BlobEyePose(both: BlobEye(width: 0.125, height: 0.26, tilt: -13), split: 48, lift: -0.01, pitch: -8)

        case .worried:
            return BlobEyePose(both: BlobEye(width: 0.115, height: 0.30, tilt: -6), split: 45, lift: 0.02, pitch: 3)

        case .focused:
            return BlobEyePose(both: BlobEye(width: 0.120, height: 0.23, tilt: 15), split: 47, lift: 0.015, pitch: 2)

        case .annoyed:
            return BlobEyePose(left: BlobEye(width: 0.130, height: 0.19, tilt: 12), right: BlobEye(width: 0.130, height: 0.27, tilt: 12), split: 49, lift: 0.015, roll: 4)

        case .surprised:
            return BlobEyePose(both: BlobEye(width: 0.145, height: 0.36, tilt: 12), split: 52, lift: 0.03)

        case .skeptic:
            return BlobEyePose(left: BlobEye(width: 0.130, height: 0.31, tilt: 22), right: BlobEye(width: 0.130, height: 0.19, tilt: 6), split: 50, lift: 0.02, roll: -5)

        case .frustrated:
            return BlobEyePose(both: BlobEye(width: 0.135, height: 0.17, tilt: 34), split: 45, lift: 0.0, pitch: -4)

        case .unimpressed:
            return BlobEyePose(both: BlobEye(width: 0.130, height: 0.16, tilt: 6), split: 50, lift: 0.01, pitch: -3)

        case .sleepy:
            return BlobEyePose(both: BlobEye(width: 0.135, height: 0.11, tilt: 14), split: 50, lift: -0.02, pitch: -8)

        case .suspicious:
            return BlobEyePose(both: BlobEye(width: 0.115, height: 0.15, tilt: 10), split: 45, lift: 0.01, yaw: 14)

        case .squint:
            return BlobEyePose(both: BlobEye(width: 0.130, height: 0.13, tilt: 22), split: 48, lift: 0.02)

        case .angry:
            return BlobEyePose(both: BlobEye(width: 0.125, height: 0.24, tilt: 40), split: 44, lift: 0.01, pitch: -2)

        case .furious:
            return BlobEyePose(both: BlobEye(width: 0.135, height: 0.22, tilt: 48), split: 42, lift: 0.0, pitch: -6)

        case .scared:
            return BlobEyePose(both: BlobEye(width: 0.115, height: 0.34, tilt: -8), split: 50, lift: 0.03, yaw: -10)

        case .awe:
            return BlobEyePose(both: BlobEye(width: 0.155, height: 0.38, tilt: 16), split: 54, lift: 0.03, pitch: 6)
        }
    }
}
