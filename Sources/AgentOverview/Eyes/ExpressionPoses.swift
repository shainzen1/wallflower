import Foundation

/// The tuned pose per expression, as plain literals so they can be adjusted by eye.
///
/// Reading the values: everything is a fraction of the face size. `topSlope` positive
/// lowers the inner (nose side) top corner, which is the angry V; negative raises it, which
/// is the sad or worried brow. `topInverseRadius` / `topInverseOffset` cut a lid-like arc
/// into the top edge; the bottom pair cuts the arc that turns a block into a smile.
/// The right eye mirrors the left unless a pose lists both.
enum ExpressionPoses {
    static func pose(for expression: Expression) -> FacePose {
        switch expression {
        case .normal:
            return FacePose(both: EyeParameters())

        case .happy:
            return FacePose(both: EyeParameters(
                width: 0.26, height: 0.30,
                topRadius: 0.85, bottomRadius: 0.4,
                bottomInverseRadius: 1.0, bottomInverseOffset: 0.50
            ))

        case .glee:
            return FacePose(both: EyeParameters(
                offsetY: -0.02,
                width: 0.28, height: 0.28,
                topRadius: 0.9, bottomRadius: 0.35,
                bottomInverseRadius: 1.0, bottomInverseOffset: 0.62
            ))

        case .sad:
            return FacePose(both: EyeParameters(
                offsetY: 0.03,
                width: 0.25, height: 0.24,
                topSlope: -0.7,
                topRadius: 0.9, bottomRadius: 0.7,
                topInverseRadius: 0.9, topInverseOffset: 0.08
            ))

        case .worried:
            return FacePose(both: EyeParameters(
                width: 0.24, height: 0.30,
                topSlope: -0.45,
                topRadius: 0.8, bottomRadius: 0.8,
                topInverseRadius: 1.0, topInverseOffset: 0.12
            ))

        case .focused:
            return FacePose(both: EyeParameters(
                width: 0.26, height: 0.19,
                topSlope: 0.12,
                topRadius: 0.45, bottomRadius: 0.7,
                topInverseRadius: 1.0, topInverseOffset: 0.06
            ))

        case .annoyed:
            return FacePose(
                left: EyeParameters(
                    offsetY: 0.01,
                    width: 0.25, height: 0.17,
                    topSlope: 0.2,
                    topRadius: 0.3, bottomRadius: 0.8
                ),
                right: EyeParameters(
                    offsetY: 0.01,
                    width: 0.25, height: 0.22,
                    topSlope: 0.05,
                    topRadius: 0.3, bottomRadius: 0.8
                )
            )

        case .surprised:
            return FacePose(both: EyeParameters(
                offsetY: -0.01,
                width: 0.26, height: 0.38,
                topRadius: 1.0, bottomRadius: 1.0
            ))

        case .skeptic:
            return FacePose(
                left: EyeParameters(
                    offsetY: -0.02,
                    width: 0.25, height: 0.32,
                    topRadius: 0.8, bottomRadius: 0.8
                ),
                right: EyeParameters(
                    offsetY: 0.03,
                    width: 0.25, height: 0.17,
                    topSlope: 0.35,
                    topRadius: 0.2, bottomRadius: 0.8
                )
            )

        case .frustrated:
            return FacePose(both: EyeParameters(
                offsetX: 0.01,
                width: 0.25, height: 0.22,
                topSlope: 0.4,
                topRadius: 0.3, bottomRadius: 0.7
            ))

        case .unimpressed:
            return FacePose(both: EyeParameters(
                offsetY: 0.02,
                width: 0.26, height: 0.15,
                topRadius: 0.25, bottomRadius: 0.9
            ))

        case .sleepy:
            return FacePose(both: EyeParameters(
                offsetY: 0.05,
                width: 0.26, height: 0.13,
                topRadius: 0.5, bottomRadius: 1.0,
                topInverseRadius: 1.0, topInverseOffset: 0.2
            ))

        case .suspicious:
            return FacePose(
                left: EyeParameters(
                    offsetY: 0.02,
                    width: 0.25, height: 0.15,
                    topSlope: 0.25,
                    topRadius: 0.3, bottomRadius: 0.8
                ),
                right: EyeParameters(
                    offsetY: 0.02,
                    width: 0.25, height: 0.20,
                    topSlope: -0.05,
                    topRadius: 0.3, bottomRadius: 0.8
                ),
                gaze: GazeOffset(x: 0.06, y: 0)
            )

        case .squint:
            return FacePose(both: EyeParameters(
                width: 0.28, height: 0.12,
                topRadius: 1.0, bottomRadius: 1.0,
                topInverseRadius: 1.0, topInverseOffset: 0.18,
                bottomInverseRadius: 1.0, bottomInverseOffset: 0.18
            ))

        case .angry:
            return FacePose(both: EyeParameters(
                offsetX: 0.01,
                width: 0.26, height: 0.26,
                topSlope: 0.55,
                topRadius: 0.25, bottomRadius: 0.8
            ))

        case .furious:
            return FacePose(both: EyeParameters(
                offsetX: 0.02, offsetY: 0.01,
                width: 0.28, height: 0.22,
                topSlope: 0.75,
                topRadius: 0.15, bottomRadius: 0.7
            ))

        case .scared:
            return FacePose(both: EyeParameters(
                offsetY: -0.02,
                width: 0.22, height: 0.38,
                topSlope: -0.3,
                topRadius: 0.9, bottomRadius: 0.9,
                bottomInverseRadius: 0.6, bottomInverseOffset: 0.08
            ))

        case .awe:
            return FacePose(both: EyeParameters(
                offsetY: -0.03,
                width: 0.28, height: 0.36,
                topRadius: 1.0, bottomRadius: 1.0,
                bottomInverseRadius: 0.9, bottomInverseOffset: 0.12
            ))
        }
    }
}
