import Foundation

/// A keyed animation of the eye paths described as poses in time: each step holds a pose,
/// then moves to the next. A repeating track loops back to its first pose (blink loops,
/// working variety); a one-shot track stops on its last pose and keeps it (drift to sleepy,
/// return to normal after a bounce). The layer tree turns a track into Core Animation
/// keyframes, so no timer ever runs in the app for these.
struct PathTrack: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        var pose: FacePose
        /// How long the pose stays before the move to the next step starts.
        var hold: TimeInterval
        /// How long the move to the next step takes.
        var transition: TimeInterval
    }

    enum Transition: Equatable, Sendable {
        /// Ease in and out between keyframes.
        case ease
        /// A pose spring (one-shot tracks with exactly two steps only).
        case spring
    }

    var key: String
    var steps: [Step]
    var repeats: Bool
    /// Seconds after installation before the track starts. Lets a later state be scheduled without a timer.
    var delay: TimeInterval = 0
    /// Start phase in [0, 1) of the total duration (repeating tracks), so faces are never in sync.
    var phase: Double = 0
    var transition: Transition = .ease

    /// Total length of one pass through the steps.
    var duration: TimeInterval {
        let total = steps.reduce(0) { $0 + $1.hold + $1.transition }
        return repeats ? total : max(total - (steps.last?.transition ?? 0), 0)
    }

    // MARK: Factories

    /// A blink loop: `open` for the interval, a quick close, open again. With `doubleEvery` n > 0
    /// the loop spans n intervals and the last blink of the loop is a double blink.
    static func blink(key: String, open: FacePose, interval: TimeInterval, phase: Double, delay: TimeInterval = 0, doubleEvery: Int = 0) -> PathTrack {
        let cycles = max(doubleEvery, 1)
        var steps: [Step] = []
        for cycle in 0..<cycles {
            let isDouble = doubleEvery > 0 && cycle == cycles - 1
            steps += blinkCycle(open: open, interval: interval, double: isDouble)
        }
        return PathTrack(key: key, steps: steps, repeats: true, delay: delay, phase: phase)
    }

    /// One blink interval as steps: `open` for the interval minus the blink, then the blink
    /// (or a double blink). The last step is the closed pose with the opening edge as its transition,
    /// so the steps chain with whatever follows. The steps add up to exactly `interval`.
    static func blinkCycle(open: FacePose, interval: TimeInterval, double: Bool) -> [Step] {
        let edge = Theme.blinkEdgeDuration
        let hold = Theme.blinkHoldDuration
        let closed = open.closed()
        if double {
            return [
                Step(pose: open, hold: interval - edge * 4 - hold * 2 - Theme.doubleBlinkGap, transition: edge),
                Step(pose: closed, hold: hold, transition: edge),
                Step(pose: open, hold: Theme.doubleBlinkGap, transition: edge),
                Step(pose: closed, hold: hold, transition: edge),
            ]
        }
        return [
            Step(pose: open, hold: interval - edge * 2 - hold, transition: edge),
            Step(pose: closed, hold: hold, transition: edge),
        ]
    }

    /// One blink right now, then back to `open`.
    static func singleBlink(key: String, open: FacePose) -> PathTrack {
        PathTrack(
            key: key,
            steps: [
                Step(pose: open, hold: 0, transition: Theme.blinkEdgeDuration),
                Step(pose: open.closed(), hold: Theme.blinkHoldDuration, transition: Theme.blinkEdgeDuration),
                Step(pose: open, hold: 0, transition: 0),
            ],
            repeats: false
        )
    }

    /// A one-shot move from one pose to another after a delay, kept afterwards.
    static func move(key: String, from: FacePose, to: FacePose, after delay: TimeInterval, duration: TimeInterval, transition: Transition) -> PathTrack {
        PathTrack(
            key: key,
            steps: [Step(pose: from, hold: 0, transition: duration), Step(pose: to, hold: 0, transition: 0)],
            repeats: false,
            delay: delay,
            transition: transition
        )
    }
}
