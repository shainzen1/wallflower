import Foundation

/// Identity shape presets. Each is a small parameter delta added on top of every expression
/// pose, so the same expression looks a little different from face to face.
enum EyePreset: String, CaseIterable, Sendable {
    case round
    case wide
    case slanted
    case sleepyLidded

    /// The delta added to both eyes of every pose. Values are fractions of the face size.
    var delta: EyeParameters {
        switch self {
        case .round:
            return EyeParameters(
                offsetX: 0, offsetY: 0, width: -0.02, height: 0.02,
                topSlope: 0, bottomSlope: 0, topRadius: 0.3, bottomRadius: 0.3,
                topInverseRadius: 0, topInverseOffset: 0, bottomInverseRadius: 0, bottomInverseOffset: 0
            )
        case .wide:
            return EyeParameters(
                offsetX: 0, offsetY: 0, width: 0.06, height: -0.03,
                topSlope: 0, bottomSlope: 0, topRadius: -0.1, bottomRadius: -0.1,
                topInverseRadius: 0, topInverseOffset: 0, bottomInverseRadius: 0, bottomInverseOffset: 0
            )
        case .slanted:
            return EyeParameters(
                offsetX: 0, offsetY: 0, width: 0.01, height: -0.02,
                topSlope: 0.15, bottomSlope: 0, topRadius: 0, bottomRadius: 0,
                topInverseRadius: 0, topInverseOffset: 0, bottomInverseRadius: 0, bottomInverseOffset: 0
            )
        case .sleepyLidded:
            return EyeParameters(
                offsetX: 0, offsetY: 0.02, width: 0.01, height: -0.05,
                topSlope: 0, bottomSlope: 0, topRadius: 0, bottomRadius: 0.1,
                topInverseRadius: 1.0, topInverseOffset: 0.08, bottomInverseRadius: 0, bottomInverseOffset: 0
            )
        }
    }

    /// Human label for the playground.
    var label: String {
        switch self {
        case .round: "round"
        case .wide: "wide"
        case .slanted: "slanted"
        case .sleepyLidded: "sleepy lidded"
        }
    }
}
