import Foundation

/// A slow opacity pulse of the eye pair: 1 to `low` and back every `period`, forever, like a
/// terminal cursor (running commands). Opacity only, the ink colour never changes.
struct BlobEyePulse: Equatable, Sendable {
    var low: Double
    var period: TimeInterval
}
