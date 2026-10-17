import QuartzCore

/// Factory for every Core Animation object the eyes use. All constants come from `Theme`.
/// Nothing here runs a timer: loops are repeating animations the render server drives,
/// and later states are scheduled with `beginTime`.
enum EyeAnimations {
    /// Keys of animations that belong to the current state and are replaced on every state change.
    static let loopPrefixes = ["loop.", "sched."]

    // MARK: Springs

    /// Pose spring on a path key path, from the current presentation value to the new path.
    static func poseSpring(keyPath: String, from: Any?, to: Any) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = Theme.poseSpringMass
        spring.stiffness = Theme.poseSpringStiffness
        spring.damping = Theme.poseSpringDamping
        spring.initialVelocity = 0
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }

    /// How long the pose spring takes to settle; used to schedule what follows it.
    static var poseSpringSettlingDuration: TimeInterval {
        poseSpring(keyPath: "path", from: nil, to: NSNull()).settlingDuration
    }

    /// Gaze spring on a translation key path.
    static func gazeSpring(keyPath: String, from: Any?, to: Any) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = Theme.gazeSpringMass
        spring.stiffness = Theme.gazeSpringStiffness
        spring.damping = Theme.gazeSpringDamping
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }

    // MARK: Exclamation dots

    /// The dot of a "!" arriving: opacity and scale spring in, `delay` after the bar started.
    /// `fillMode` backwards keeps the dot hidden until its begin time although the model is already visible.
    static func dotEnter(delay: TimeInterval, now: CFTimeInterval) -> [(key: String, animation: CAAnimation)] {
        let opacity = poseSpring(keyPath: "opacity", from: 0, to: 1)
        let scale = poseSpring(keyPath: "transform.scale", from: Theme.exclamationDotHiddenScale, to: 1)
        for spring in [opacity, scale] {
            spring.beginTime = now + delay
            spring.fillMode = .backwards
        }
        return [("dot.opacity", opacity), ("dot.scale", scale)]
    }

    /// The dot leaving: a quick ease out to hidden, faster than it came in.
    static func dotExit(fromOpacity: Any?, fromScale: Any?) -> [(key: String, animation: CAAnimation)] {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = 0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = fromScale
        scale.toValue = Theme.exclamationDotHiddenScale
        for animation in [opacity, scale] {
            animation.duration = Theme.exclamationDotExitDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        }
        return [("dot.opacity", opacity), ("dot.scale", scale)]
    }

    // MARK: Path tracks

    /// Turns a `PathTrack` into the animation for one layer key path.
    /// - Parameters:
    ///   - now: the layer's current local time (`convertTime(CACurrentMediaTime(), from: nil)`).
    ///   - path: maps a pose to the path this layer needs (left or right eye).
    static func animation(for track: PathTrack, keyPath: String, now: CFTimeInterval, path: (FacePose) -> CGPath) -> CAAnimation {
        if !track.repeats, track.transition == .spring, track.steps.count == 2 {
            let spring = poseSpring(keyPath: keyPath, from: path(track.steps[0].pose), to: path(track.steps[1].pose))
            spring.beginTime = now + track.delay + track.steps[0].hold
            spring.fillMode = .forwards
            spring.isRemovedOnCompletion = false
            return spring
        }

        var times: [TimeInterval] = []
        var poses: [FacePose] = []
        var functions: [CAMediaTimingFunction] = []
        let hold = CAMediaTimingFunction(name: .linear)
        let move = CAMediaTimingFunction(name: .easeInEaseOut)
        var t: TimeInterval = 0
        for (index, step) in track.steps.enumerated() {
            times.append(t)
            poses.append(step.pose)
            t += step.hold
            times.append(t)
            poses.append(step.pose)
            functions.append(hold)
            let isLast = index == track.steps.count - 1
            if track.repeats || !isLast {
                t += step.transition
                functions.append(move)
            }
        }
        if track.repeats, let first = track.steps.first {
            times.append(t)
            poses.append(first.pose)
        }
        let duration = max(t, 0.001)

        let keyframes = CAKeyframeAnimation(keyPath: keyPath)
        keyframes.values = poses.map { path($0) }
        keyframes.keyTimes = times.map { NSNumber(value: $0 / duration) }
        keyframes.timingFunctions = functions
        keyframes.calculationMode = .linear
        keyframes.duration = duration
        if track.repeats {
            keyframes.repeatCount = .infinity
            keyframes.timeOffset = track.phase * duration
        } else {
            keyframes.fillMode = .forwards
            keyframes.isRemovedOnCompletion = track.key.hasPrefix("oneshot.")
        }
        if track.delay > 0 {
            keyframes.beginTime = now + track.delay
        }
        return keyframes
    }

    // MARK: Loops on transform and glow (all additive, so gaze and bounce still apply)

    /// Working glance: wait, left, hold, back, wait a little longer, right, hold, back.
    static func dart(amplitude: CGFloat, interval: TimeInterval, phase: Double) -> CAKeyframeAnimation {
        let move = Theme.dartMove
        let hold = Theme.dartHold
        var times: [TimeInterval] = []
        var values: [CGFloat] = []
        func add(_ time: TimeInterval, _ value: CGFloat) {
            times.append(time)
            values.append(value)
        }
        var t: TimeInterval = 0
        add(t, 0)
        t += interval; add(t, 0)
        t += move; add(t, -amplitude)
        t += hold; add(t, -amplitude)
        t += move; add(t, 0)
        t += interval * 1.25; add(t, 0)
        t += move; add(t, amplitude)
        t += hold; add(t, amplitude)
        t += move; add(t, 0)
        return loop(keyPath: "transform.translation.x", values: values, times: times, phase: phase, alternateEasing: true)
    }

    /// Working: slow vertical reading scan, down and up.
    static func scan(amplitude: CGFloat, phase: Double) -> CAKeyframeAnimation {
        let period = Theme.scanPeriod
        let values: [CGFloat] = [0, -amplitude, 0, amplitude, 0]
        let times = (0..<values.count).map { period * Double($0) / Double(values.count - 1) }
        return loop(keyPath: "transform.translation.y", values: values, times: times, phase: phase, alternateEasing: false)
    }

    /// Idle: the gaze drifts round a tiny ellipse. Two animations, x and y, sampled from one period.
    static func wander(radiusX: CGFloat, radiusY: CGFloat, phase: Double) -> [(key: String, animation: CAKeyframeAnimation)] {
        let samples = 16
        let period = Theme.wanderPeriod
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        var times: [TimeInterval] = []
        for index in 0...samples {
            let angle = Double(index) / Double(samples) * 2 * Double.pi
            xs.append(radiusX * CGFloat(cos(angle)))
            ys.append(radiusY * CGFloat(sin(angle)))
            times.append(period * Double(index) / Double(samples))
        }
        return [
            ("loop.wander.x", loop(keyPath: "transform.translation.x", values: xs, times: times, phase: phase, alternateEasing: false, linear: true)),
            ("loop.wander.y", loop(keyPath: "transform.translation.y", values: ys, times: times, phase: phase, alternateEasing: false, linear: true)),
        ]
    }

    /// Scale breath of the eye pair: 1.0 to `scale` and back. Additive, so it adds to the model scale of 1.
    static func breath(_ breath: BreathLoop, phase: Double, now: CFTimeInterval) -> CAKeyframeAnimation {
        let delta = CGFloat(breath.scale - 1)
        let values: [CGFloat] = [0, delta, 0]
        let times: [TimeInterval] = [0, breath.period / 2, breath.period]
        let animation = loop(keyPath: "transform.scale", values: values, times: times, phase: phase, alternateEasing: false)
        if breath.delay > 0 {
            animation.beginTime = now + breath.delay
        }
        return animation
    }

    /// A repeating additive keyframe loop. `alternateEasing` uses linear for holds and ease for moves
    /// (the dart pattern: hold, move, hold, move...); otherwise every segment eases, or is linear.
    private static func loop(keyPath: String, values: [CGFloat], times: [TimeInterval], phase: Double, alternateEasing: Bool, linear: Bool = false) -> CAKeyframeAnimation {
        let duration = times.last ?? 1
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0 / duration) }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let straight = CAMediaTimingFunction(name: .linear)
        let segments = values.count - 1
        if alternateEasing {
            animation.timingFunctions = (0..<segments).map { $0 % 2 == 0 ? straight : ease }
        } else {
            animation.timingFunctions = Array(repeating: linear ? straight : ease, count: segments)
        }
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = phase * duration
        animation.isAdditive = true
        return animation
    }

    /// Slow swing between two values, forever.
    static func pulse(keyPath: String, from: Any, to: Any, phase: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.pulseHalfDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.timeOffset = phase * Theme.pulseHalfDuration * 2
        return animation
    }

    /// The finished bounce on scale.
    static func bounce() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = Theme.bounceScales
        let count = Theme.bounceScales.count
        animation.keyTimes = (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: count - 1)
        animation.duration = Theme.bounceDuration
        return animation
    }

    /// A face arriving (`RowEntrance.FaceTiming`): invisible until `timing.delay` after `now` (the
    /// layer's local time), then a short ease-out fade-in and a spring from `Theme.rowEnterScale` to 1
    /// with a small overshoot (`Theme.rowEnterSpring` as Core Animation physics). Reduce Motion keeps
    /// only the fade. Non-additive on `transform.scale` of the face layer; the magnification above it
    /// and the rest scale below it compose untouched.
    static func enter(_ timing: RowEntrance.FaceTiming, now: CFTimeInterval) -> CAAnimationGroup {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = timing.fadeDuration
        opacity.timingFunction = BlobAnimations.easeOut
        var animations: [CAAnimation] = [opacity]
        var duration = timing.fadeDuration
        if !timing.reduceMotion {
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.mass = timing.spring.mass
            spring.stiffness = timing.spring.stiffness
            spring.damping = timing.spring.damping
            spring.initialVelocity = 0
            spring.fromValue = timing.fromScale
            spring.toValue = 1
            spring.duration = spring.settlingDuration
            animations.append(spring)
            duration = max(duration, spring.duration)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.beginTime = now + timing.delay
        group.fillMode = .backwards
        return group
    }

    /// Reduce Motion pose change: a crossfade of the whole face layer.
    static func crossfade() -> CATransition {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = Theme.reduceMotionFadeDuration
        return transition
    }

    /// Colour change on a colour key path.
    static func color(keyPath: String, from: CGColor?, to: CGColor) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.colorChangeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// Colour flash: ease to `flash`, hold it for `Theme.doneHold`, ease to `to` (the model value).
    static func colorFlash(keyPath: String, from: CGColor?, flash: CGColor, to: CGColor) -> CAKeyframeAnimation {
        let change = Theme.colorChangeDuration
        let hold = Theme.doneHold
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let values: [CGColor]
        if let from {
            let total = change * 2 + hold
            values = [from, flash, flash, to]
            animation.keyTimes = [0, NSNumber(value: change / total), NSNumber(value: (change + hold) / total), 1]
            animation.duration = total
        } else {
            let total = change + hold
            values = [flash, flash, to]
            animation.keyTimes = [0, NSNumber(value: hold / total), 1]
            animation.duration = total
        }
        animation.values = values
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        return animation
    }

    /// Glow strength change (shadow opacity).
    static func glow(from: Any?, to: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.colorChangeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}
