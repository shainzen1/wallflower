import Foundation

/// A body change that happens later without a timer (the sleepy sag): the body to morph to,
/// when, and how long the ease-out takes. The layer tree schedules it with `beginTime`.
struct BlobScheduledBody: Equatable, Sendable {
    var body: BlobBody
    var after: TimeInterval
    var duration: TimeInterval
}
