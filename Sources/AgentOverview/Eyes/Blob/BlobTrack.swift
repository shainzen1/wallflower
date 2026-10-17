import Foundation

/// A keyed animation of the blob eyes: the pose sampled over time, turned into path keyframes
/// by the layer tree. Loops are pure functions of time (gaze drift, wander, a blink schedule)
/// sampled on a regular grid plus the blink edges, so no timer ever runs in the app.
struct BlobTrack: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        var time: TimeInterval
        var pose: BlobEyePose
    }

    var key: String
    var samples: [Sample]
    var repeats: Bool
    /// Seconds after installation before the track starts (later states without a timer).
    var delay: TimeInterval = 0

    var duration: TimeInterval {
        samples.last?.time ?? 0
    }

    // MARK: Factories

    /// Samples `pose(t)` every `Theme.blobSampleStep` over `duration`, plus every time in `events`
    /// (blink edges, move starts), so fast features are not missed.
    static func sampled(key: String, duration: TimeInterval, repeats: Bool, delay: TimeInterval = 0, events: [TimeInterval] = [], pose: (TimeInterval) -> BlobEyePose) -> BlobTrack {
        var times: Set<Int> = []
        let resolution = 1000.0
        var t = 0.0
        while t < duration {
            times.insert(Int((t * resolution).rounded()))
            t += Theme.blobSampleStep
        }
        for event in events where event >= 0 && event <= duration {
            times.insert(Int((event * resolution).rounded()))
        }
        times.insert(Int((duration * resolution).rounded()))
        let samples = times.sorted().map { Sample(time: Double($0) / resolution, pose: pose(Double($0) / resolution)) }
        return BlobTrack(key: key, samples: compact(samples), repeats: repeats, delay: delay)
    }

    /// Drops the interior samples of constant stretches (a pose that only blinks is constant most
    /// of the time); linear keyframes between the survivors reproduce the run exactly.
    private static func compact(_ samples: [Sample]) -> [Sample] {
        guard samples.count > 2 else { return samples }
        var kept: [Sample] = [samples[0]]
        for index in 1..<(samples.count - 1) {
            let (previous, current, next) = (samples[index - 1].pose, samples[index].pose, samples[index + 1].pose)
            if previous == current && current == next { continue }
            kept.append(samples[index])
        }
        kept.append(samples[samples.count - 1])
        return kept
    }

    /// One blink right now from `open`, then back.
    static func singleBlink(key: String, open: BlobEyePose) -> BlobTrack {
        let schedule = BlobBlinkSchedule(starts: [0])
        return sampled(key: key, duration: schedule.blinkLength, repeats: false, events: schedule.events) { t in
            open.withLid(schedule.lid(at: t))
        }
    }

    /// A face arriving: the lids stay closed until `opensAt`, then open onto `open` over
    /// `Theme.blobBlinkOpen` (the second half of a blink). Not repeating.
    static func openingEyes(key: String, open: BlobEyePose, opensAt: TimeInterval) -> BlobTrack {
        let closed = open.closed()
        let duration = opensAt + Theme.blobBlinkOpen
        return sampled(key: key, duration: duration, repeats: false, events: [opensAt]) { t in
            guard t > opensAt else { return closed }
            return BlobEyePose.lerp(closed, open, t: BlobMotion.easeOut(min((t - opensAt) / Theme.blobBlinkOpen, 1)))
        }
    }

    /// A one-shot move between two poses after a delay, eased out, kept afterwards.
    static func move(key: String, from: BlobEyePose, to: BlobEyePose, after delay: TimeInterval, duration: TimeInterval) -> BlobTrack {
        sampled(key: key, duration: duration, repeats: false, delay: delay) { t in
            BlobEyePose.lerp(from, to, t: BlobMotion.easeOut(t / duration))
        }
    }

    /// A change hidden in a blink: close on `from`, swap to `to` while closed, open on `to`. Kept afterwards.
    static func blinkSwap(key: String, from: BlobEyePose, to: BlobEyePose, after delay: TimeInterval = 0) -> BlobTrack {
        let schedule = BlobBlinkSchedule(starts: [0])
        let swap = Theme.blobBlinkClose + Theme.blobBlinkHold / 2
        return sampled(key: key, duration: schedule.blinkLength, repeats: false, delay: delay, events: schedule.events + [swap]) { t in
            (t < swap ? from : to).withLid(schedule.lid(at: t))
        }
    }
}
