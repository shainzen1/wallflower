import Foundation

/// The periodic grow of a waiting face: the body scales to `scale` and back within `duration`
/// (up for `upFraction` of it, ease-out; down the rest, ease-in-out), once every `interval`.
struct AttentionGrow: Equatable, Sendable {
    var scale: Double
    var duration: TimeInterval
    var interval: TimeInterval
    var upFraction: Double
}
