import Foundation

/// Blink start times inside one loop and the lid value they produce at any time: a quick close,
/// a short hold at the sliver, a slower open. Deterministic, so loops sampled from it are too.
struct BlobBlinkSchedule: Sendable {
    var starts: [TimeInterval]
    /// Stretches every blink (close, hold, open) by this factor: 1 is the normal blink, more is a slow one.
    var durationScale: Double = 1

    private var close: TimeInterval { Theme.blobBlinkClose * durationScale }
    private var hold: TimeInterval { Theme.blobBlinkHold * durationScale }
    private var open: TimeInterval { Theme.blobBlinkOpen * durationScale }

    var blinkLength: TimeInterval {
        close + hold + open
    }

    /// Blinks every `interval` for `count` intervals, the loop phase shifted by `phase` so faces
    /// never blink together; every `doubleEvery`-th blink is a double blink.
    init(interval: TimeInterval, count: Int, phase: Double, doubleEvery: Int = 0, durationScale: Double = 1) {
        var starts: [TimeInterval] = []
        let offset = phase * interval
        let length = (Theme.blobBlinkClose + Theme.blobBlinkHold + Theme.blobBlinkOpen) * durationScale
        for cycle in 0..<count {
            let start = offset + Double(cycle) * interval + interval * 0.6
            starts.append(start)
            if doubleEvery > 0, (cycle + 1) % doubleEvery == 0 {
                starts.append(start + length + Theme.doubleBlinkGap)
            }
        }
        let total = interval * Double(count)
        self.starts = starts.map { $0.truncatingRemainder(dividingBy: total) }.sorted()
        self.durationScale = durationScale
    }

    init(starts: [TimeInterval], durationScale: Double = 1) {
        self.starts = starts
        self.durationScale = durationScale
    }

    /// Sample times the sampler must hit: the four corners of every blink.
    var events: [TimeInterval] {
        starts.flatMap { start in
            [start, start + close, start + close + hold, start + blinkLength]
        }
    }

    /// Lid at `t`: 1 open, `Theme.blobClosedLid` at the hold.
    func lid(at t: TimeInterval) -> Double {
        var lid = 1.0
        for start in starts {
            let local = t - start
            guard local >= 0, local <= blinkLength else { continue }
            let closed = Theme.blobClosedLid
            if local < close {
                lid = min(lid, 1 - (1 - closed) * (local / close))
            } else if local < close + hold {
                lid = min(lid, closed)
            } else {
                let opening = (local - close - hold) / open
                lid = min(lid, closed + (1 - closed) * BlobMotion.easeOut(opening))
            }
        }
        return lid
    }
}
