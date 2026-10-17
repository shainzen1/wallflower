import Foundation

/// A slow scale "breath" of the eye pair: 1.0 to `scale` and back over `period`, forever,
/// starting `delay` seconds after installation (so it can wait for a bounce to finish).
struct BreathLoop: Equatable, Sendable {
    var scale: Double
    var period: TimeInterval
    var delay: TimeInterval = 0
}
