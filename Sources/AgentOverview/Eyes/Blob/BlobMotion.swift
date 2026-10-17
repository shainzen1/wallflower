import Foundation

/// The curves the blob faces move on: exponential ease-outs that never overshoot.
enum BlobMotion {
    /// Exponential ease-out on [0, 1]: fast start, long settle, exactly 1 at the end.
    static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        if t >= 1 { return 1 }
        return 1 - pow(2, -10 * t) * (1 - t)
    }

    /// Gaze along a script of targets: each target is reached by an ease-out of `moveDuration`
    /// (`Theme.blobGazeMoveDuration` by default) starting at its time, from the previous target.
    static func gaze(at t: TimeInterval, targets: [(time: Double, yaw: Double, pitch: Double)], moveDuration: TimeInterval = Theme.blobGazeMoveDuration) -> (yaw: Double, pitch: Double) {
        guard let first = targets.first else { return (0, 0) }
        var previous = (yaw: first.yaw, pitch: first.pitch)
        var current = previous
        var start = first.time
        for target in targets where target.time <= t {
            previous = current
            current = (target.yaw, target.pitch)
            start = target.time
        }
        let p = easeOut((t - start) / moveDuration)
        return (previous.yaw + (current.yaw - previous.yaw) * p, previous.pitch + (current.pitch - previous.pitch) * p)
    }
}
