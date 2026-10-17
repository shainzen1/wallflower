import Foundation

/// What an action face is doing: resting (calm, sleepy eyes), hovered (eyes open to normal) or
/// launching (the working cloud right after a click, until the feedback time is over).
enum ActionFacePhase: Equatable, Sendable {
    case resting
    case hovered
    case launching
}
