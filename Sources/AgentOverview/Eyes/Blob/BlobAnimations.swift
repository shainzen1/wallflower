import QuartzCore

/// Core Animation factory for the blob faces. Loops are repeating keyframe animations the render
/// server drives; later states are scheduled with `beginTime`. Curves are ease-outs, never springs,
/// with one exception: the genie stretch of a hovered face is elastic on purpose.
enum BlobAnimations {
    /// Keys of animations that belong to the current state and are replaced on every state change.
    static let loopPrefixes = ["loop.", "sched."]

    /// A strong ease-out (close to an exponential ease-out) as a Core Animation timing function.
    static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) }

    /// Turns a sampled track into path keyframes for one eye layer.
    /// - Parameters:
    ///   - now: the layer's current local time.
    ///   - firstValue: replaces the first keyframe (the path on screen right now, mid-animation).
    ///   - path: maps a pose to the path this layer needs (left or right eye).
    static func keyframes(for track: BlobTrack, now: CFTimeInterval, firstValue: CGPath? = nil, path: (BlobEyePose) -> CGPath) -> CAKeyframeAnimation {
        let duration = max(track.duration, 0.001)
        var values = track.samples.map { path($0.pose) }
        if let firstValue, !values.isEmpty {
            values[0] = firstValue
        }
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = values
        animation.keyTimes = track.samples.map { NSNumber(value: $0.time / duration) }
        animation.calculationMode = .linear
        animation.duration = duration
        if track.repeats {
            animation.repeatCount = .infinity
        } else {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = track.key.hasPrefix("oneshot.")
        }
        if track.delay > 0 {
            animation.beginTime = now + track.delay
        }
        return animation
    }

    /// Body morph on a path key path (`path`, or the halo's `shadowPath`): holds `from` for `delay`
    /// (the lids closing), then eases out to `to` over `duration`. `keep` leaves the final value on
    /// screen (scheduled changes whose model value is not updated); otherwise the model is already
    /// `to` and the animation goes away.
    static func morph(keyPath: String = "path", from: CGPath?, to: CGPath, delay: TimeInterval, duration: TimeInterval, now: CFTimeInterval, keep: Bool) -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        let from = from ?? to
        animation.values = [from, from, to]
        let total = max(delay + duration, 0.001)
        animation.keyTimes = [0, NSNumber(value: delay / total), 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), easeOut]
        animation.duration = total
        if keep {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        return animation
    }

    /// Just finished: one soft scale bounce 1 to `Theme.blobBounceScale` and back, ease-out both ways.
    static func bounce() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, Theme.blobBounceScale, 1.0]
        animation.keyTimes = [0, 0.42, 1]
        animation.timingFunctions = [easeOut, easeOut]
        animation.duration = Theme.blobBounceDuration
        return animation
    }

    // MARK: Working substates

    /// Running: the eye pair's opacity drops to `pulse.low` and back every period, a cursor blink
    /// (holds at each level, short eased edges). Repeats forever on the eye layers.
    static func eyePulse(_ pulse: BlobEyePulse, delay: TimeInterval, now: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1.0, 1.0, pulse.low, pulse.low, 1.0]
        animation.keyTimes = [0, 0.44, 0.5, 0.94, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), easeOut, CAMediaTimingFunction(name: .linear), easeOut]
        animation.duration = pulse.period
        animation.repeatCount = .infinity
        if delay > 0 {
            animation.beginTime = now + delay
        }
        return animation
    }

    // MARK: Attention grow

    /// The periodic grow of a waiting body: additive scale to `grow.scale` (ease-out), back (ease-in-out),
    /// then still until the interval is over. Repeats forever; `phase` shifts it so faces never sync.
    static func grow(_ grow: AttentionGrow, phase: Double) -> CAKeyframeAnimation {
        let delta = grow.scale - 1
        let up = grow.duration * grow.upFraction
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [0.0, delta, 0.0, 0.0]
        animation.keyTimes = [0, NSNumber(value: up / grow.interval), NSNumber(value: grow.duration / grow.interval), 1]
        animation.timingFunctions = [easeOut, CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        animation.duration = grow.interval
        animation.repeatCount = .infinity
        animation.timeOffset = phase * grow.interval
        animation.isAdditive = true
        return animation
    }

    /// The halo's opacity in step with the grow: rest between grows, the peak at the top of each grow,
    /// the same keyframe times as `grow(_:phase:)` so the two never drift apart.
    static func haloGrow(_ halo: BlobHalo, grow: AttentionGrow, phase: Double) -> CAKeyframeAnimation {
        let rest = halo.opacity * halo.restFraction
        let up = grow.duration * grow.upFraction
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [rest, halo.opacity, rest, rest]
        animation.keyTimes = [0, NSNumber(value: up / grow.interval), NSNumber(value: grow.duration / grow.interval), 1]
        animation.timingFunctions = [easeOut, CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        animation.duration = grow.interval
        animation.repeatCount = .infinity
        animation.timeOffset = phase * grow.interval
        return animation
    }

    /// The halo breathing: rest to peak and back every period (ease in and out, close to a sine), forever.
    static func haloBreath(_ halo: BlobHalo, breath: BreathLoop, phase: Double) -> CAKeyframeAnimation {
        let rest = halo.opacity * halo.restFraction
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [rest, halo.opacity, rest]
        animation.keyTimes = [0, 0.5, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = breath.period
        animation.repeatCount = .infinity
        animation.timeOffset = phase * breath.period
        return animation
    }

    /// The halo appearing or leaving: an eased opacity change from what is on screen.
    static func haloFade(from: Any?, to: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.haloFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// The body's rest scale changing (a face starts or stops waiting, or a hover takes the attention
    /// scale over and hands it back): an eased change of the model scale over `duration`.
    static func restScale(from: Double, to: Double, duration: TimeInterval = Theme.blobMorphDuration) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = easeOut
        return animation
    }

    // MARK: Done burst

    /// One burst dot flying from `start` to `end` (offsets from the face centre at `centre`), shrinking
    /// and fading, ease-out, starting `Theme.doneBurstDelay` after `now` (the lids are closed by then)
    /// and kept at both ends so the layer sits hidden before and can be removed cleanly afterwards.
    static func burstDot(centre: CGPoint, start: CGPoint, end: CGPoint, now: CFTimeInterval) -> CAAnimationGroup {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [CGPoint(x: centre.x + start.x, y: centre.y + start.y), CGPoint(x: centre.x + end.x, y: centre.y + end.y)]
        position.keyTimes = [0, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 1.0, 0.0]
        opacity.keyTimes = [0, 0.3, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, Theme.doneBurstEndScale]
        scale.keyTimes = [0, 1]
        let group = CAAnimationGroup()
        group.animations = [position, opacity, scale]
        group.duration = Theme.doneBurstDuration
        group.timingFunction = easeOut
        group.beginTime = now + Theme.doneBurstDelay
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        return group
    }

    // MARK: Genie stretch (hover)

    /// A spring from the value on screen to `to` on any key path: the stretch spring on hover-enter
    /// (visible overshoot), the tighter exit spring on leave. Under Reduce Motion a plain ease instead.
    static func genie(keyPath: String, from: Any?, to: Any, entering: Bool, reduceMotion: Bool) -> CAAnimation {
        if reduceMotion {
            let ease = CABasicAnimation(keyPath: keyPath)
            ease.fromValue = from
            ease.toValue = to
            ease.duration = Theme.genieReduceMotionDuration
            ease.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return ease
        }
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = Theme.genieSpringMass
        spring.stiffness = entering ? Theme.genieSpringStiffness : Theme.genieExitSpringStiffness
        spring.damping = entering ? Theme.genieSpringDamping : Theme.genieExitSpringDamping
        spring.initialVelocity = 0
        spring.fromValue = from
        spring.toValue = to
        spring.duration = spring.settlingDuration
        return spring
    }

    // MARK: Magnification (hover)

    /// The magnify layer easing from the transform on screen to `to`: a short ease-out after a pointer
    /// move (the next move replaces it, starting again from the presentation value, so the motion
    /// never jumps), the longer release when the pointer left.
    static func magnify(from: CATransform3D, to: CATransform3D, releasing: Bool) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = releasing ? Theme.magnifyReleaseDuration : Theme.magnifyFollowDuration
        animation.timingFunction = releasing ? CAMediaTimingFunction(name: .easeInEaseOut) : easeOut
        return animation
    }

    // MARK: Your turn: shape swap and hop

    /// The body path swapping between `first` (the resting path, the model value) and `second`: a
    /// morph (ease-in-out), a hold, the morph back, a hold; forever from `begin` (layer time). It starts
    /// on `first`, so nothing jumps while it waits for `begin`.
    /// The halo runs the same keyframes on `shadowPath` with its own (scaled) paths.
    static func shapeSwap(keyPath: String = "path", first: CGPath, second: CGPath, swap: BlobShapeSwap, begin: CFTimeInterval) -> CAKeyframeAnimation {
        let period = swap.period
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = [first, second, second, first, first]
        animation.keyTimes = [0, swap.duration, swap.duration + swap.hold, 2 * swap.duration + swap.hold, period].map { NSNumber(value: $0 / period) }
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        let linear = CAMediaTimingFunction(name: .linear)
        animation.timingFunctions = [easeInOut, linear, easeInOut, linear]
        animation.duration = period
        animation.repeatCount = .infinity
        animation.beginTime = begin
        return animation
    }

    /// The hop that goes with every swap, on the scaler: up by `swap.bounceHeight` of the face (ease-out),
    /// down (ease-in), a tiny squash on landing. Additive, so it rides on the rest scale; forever from
    /// `begin`, in step with `shapeSwap`.
    static func swapBounce(_ swap: BlobShapeSwap, size: CGFloat, begin: CFTimeInterval) -> CAAnimationGroup {
        var animations: [CAAnimation] = []
        let air = Theme.yourTurnBounceDuration
        for start in swap.swapTimes {
            animations.append(swapLiftPart(swap, size: size, start: start))
            for (keyPath, scale) in [("transform.scale.x", Theme.yourTurnSquashScaleX), ("transform.scale.y", Theme.yourTurnSquashScaleY)] {
                let squash = CAKeyframeAnimation(keyPath: keyPath)
                squash.values = [0.0, scale - 1, 0.0]
                squash.keyTimes = [0, 0.4, 1]
                squash.timingFunctions = [easeOut, CAMediaTimingFunction(name: .easeInEaseOut)]
                squash.beginTime = start + air
                squash.duration = Theme.yourTurnSquashDuration
                squash.isAdditive = true
                animations.append(squash)
            }
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = swap.period
        group.repeatCount = .infinity
        group.beginTime = begin
        return group
    }

    /// The glow lifting with every hop of `swapBounce`: the same lift keyframes, curves, beat and
    /// period (no squash, that stays on the body), on the halo's host. Forever from `begin`, which the
    /// layer tree sets to the scaler's begin time, so body and glow leave and land together.
    static func swapLift(_ swap: BlobShapeSwap, size: CGFloat, begin: CFTimeInterval) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = swap.swapTimes.map { swapLiftPart(swap, size: size, start: $0) }
        group.duration = swap.period
        group.repeatCount = .infinity
        group.beginTime = begin
        return group
    }

    /// One your-turn hop's lift: up by `swap.bounceHeight` of the face (ease-out), down (ease-in),
    /// additive, starting `start` into the period. Shared by the body's hop and the glow's lift.
    private static func swapLiftPart(_ swap: BlobShapeSwap, size: CGFloat, start: TimeInterval) -> CAKeyframeAnimation {
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = [0.0, Double(size) * swap.bounceHeight, 0.0]
        lift.keyTimes = [0, NSNumber(value: Theme.yourTurnBounceUpFraction), 1]
        lift.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        lift.beginTime = start
        lift.duration = Theme.yourTurnBounceDuration
        lift.isAdditive = true
        return lift
    }

    /// A paused or ended swap: the body path (or the halo's) eases from what is on screen to the resting one.
    static func swapSettle(keyPath: String = "path", from: CGPath?, to: CGPath) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Theme.yourTurnSettleDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// The glow swelling with every hop of `swapBounce`: an additive scale up to `Theme.haloHopSwell`
    /// while the face is in the air (ease-in-out), fullest at the top of the landing squash, back to
    /// nothing over `Theme.haloHopSwellRelease` (ease-out). Forever from `begin`, in step with the hop.
    static func haloSwell(_ swap: BlobShapeSwap, begin: CFTimeInterval) -> CAAnimationGroup {
        let rise = Theme.yourTurnBounceDuration + Theme.yourTurnSquashDuration * 0.4
        let total = rise + Theme.haloHopSwellRelease
        var animations: [CAAnimation] = []
        for start in swap.swapTimes {
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [0.0, Theme.haloHopSwell - 1, 0.0]
            swell.keyTimes = [0, NSNumber(value: rise / total), 1]
            swell.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), easeOut]
            swell.beginTime = start
            swell.duration = total
            swell.isAdditive = true
            animations.append(swell)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = swap.period
        group.repeatCount = .infinity
        group.beginTime = begin
        return group
    }

    /// A paused or ended swell: the scale on screen (`from`, added to the model) eases back to nothing.
    static func swellSettle(from: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = 0
        animation.duration = Theme.yourTurnSettleDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.isAdditive = true
        return animation
    }

    /// A paused or ended hop: the lift on screen (`from`, points) eases down to nothing, additive.
    static func bounceSettle(from: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = from
        animation.toValue = 0
        animation.duration = Theme.yourTurnSettleDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.isAdditive = true
        return animation
    }

    // MARK: Attention hop

    /// The whole face hops once: up by `Theme.hopHeight` of the face (ease-out), back down
    /// (ease-in-out), and a tiny squash on landing that releases within `Theme.hopSquashDuration`.
    static func hop(size: CGFloat) -> CAAnimationGroup {
        let duration = Theme.hopDuration
        let total = duration + Theme.hopSquashDuration
        let lift = hopLift(size: size)

        let squash = Theme.hopSquashDuration
        let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scaleX.values = [1.0, Theme.hopSquashScaleX, 1.0]
        let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        scaleY.values = [1.0, Theme.hopSquashScaleY, 1.0]
        for scale in [scaleX, scaleY] {
            scale.keyTimes = [0, 0.4, 1]
            scale.timingFunctions = [easeOut, easeOut]
            scale.beginTime = duration
            scale.duration = squash
        }
        let group = CAAnimationGroup()
        group.animations = [lift, scaleX, scaleY]
        group.duration = total
        return group
    }

    /// The attention hop's lift alone: up by `Theme.hopHeight` of the face (ease-out), back down
    /// (ease-in-out) over `Theme.hopDuration`. Inside `hop(size:)` on the face; the glow's host runs the
    /// same animation (additive there, the host's model transform is identity) and so lifts with the
    /// body on the same clock, without the squash.
    static func hopLift(size: CGFloat, additive: Bool = false) -> CAKeyframeAnimation {
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = [0, size * Theme.hopHeight, 0]
        lift.keyTimes = [0, NSNumber(value: Theme.hopUpFraction), 1]
        lift.timingFunctions = [easeOut, CAMediaTimingFunction(name: .easeInEaseOut)]
        lift.duration = Theme.hopDuration
        lift.isAdditive = additive
        return lift
    }

    // MARK: Excited (the person's message arrived)

    /// The two hops of the excited reaction: the first `Theme.excitedHopHeight` of the face over
    /// `Theme.excitedHopDuration`, the second `Theme.excitedSecondHop` as high right after it, each
    /// ease-out up and ease-in down. Additive, from `begin` (layer time); on the face, and on the
    /// glow's host so the glow lifts with it (the squash and the wiggle stay on the body).
    static func excitedHops(size: CGFloat, begin: CFTimeInterval) -> CAAnimationGroup {
        let first = Theme.excitedHopDuration
        let second = first * Theme.excitedSecondHopTime
        var animations: [CAAnimation] = []
        for (start, duration, height) in [(0.0, first, 1.0), (first, second, Theme.excitedSecondHop)] {
            let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
            lift.values = [0.0, Double(size) * Theme.excitedHopHeight * height, 0.0]
            lift.keyTimes = [0, NSNumber(value: Theme.excitedHopUpFraction), 1]
            lift.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            lift.beginTime = start
            lift.duration = duration
            lift.isAdditive = true
            animations.append(lift)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = first + second
        group.beginTime = begin
        return group
    }

    /// When the second excited hop lands, from the start of the reaction.
    static var excitedLanding: TimeInterval {
        Theme.excitedHopDuration * (1 + Theme.excitedSecondHopTime)
    }

    /// The body's share of the excited reaction, on the scaler: a wiggle over the two hops (tilt one
    /// way, the other, half back, settle; ease in and out) and a tiny squash on the second landing.
    /// Additive, from `begin` (layer time).
    static func excitedWiggle(begin: CFTimeInterval) -> CAAnimationGroup {
        let landing = excitedLanding
        let angle = Theme.excitedWiggleAngle
        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [0.0, angle, -angle, angle / 2, 0.0]
        wiggle.keyTimes = [0, 0.22, 0.55, 0.8, 1]
        wiggle.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        wiggle.duration = landing
        wiggle.isAdditive = true
        var animations: [CAAnimation] = [wiggle]
        for (keyPath, scale) in [("transform.scale.x", Theme.excitedSquashScaleX), ("transform.scale.y", Theme.excitedSquashScaleY)] {
            let squash = CAKeyframeAnimation(keyPath: keyPath)
            squash.values = [0.0, scale - 1, 0.0]
            squash.keyTimes = [0, 0.4, 1]
            squash.timingFunctions = [easeOut, CAMediaTimingFunction(name: .easeInEaseOut)]
            squash.beginTime = landing
            squash.duration = Theme.excitedSquashDuration
            squash.isAdditive = true
            animations.append(squash)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = landing + Theme.excitedSquashDuration
        group.beginTime = begin
        return group
    }

    /// The body brightening with the excited reaction: from the colour on screen (`from`, still easing
    /// out of the old state's) to `color` over `wait` (the blink of the state change), up to `bright`
    /// within `Theme.excitedBrightPeak` (ease-out), back to `color` by `Theme.excitedDuration`
    /// (ease in and out). It replaces the state change's colour ease, so the colour never jumps.
    static func excitedColor(from: CGColor?, to color: CGColor, bright: CGColor, wait: TimeInterval) -> CAKeyframeAnimation {
        let total = wait + Theme.excitedDuration
        let animation = CAKeyframeAnimation(keyPath: "fillColor")
        animation.values = [from ?? color, color, bright, color]
        animation.keyTimes = [0, wait, wait + Theme.excitedBrightPeak, total].map { NSNumber(value: $0 / total) }
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), easeOut, CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = total
        return animation
    }

    // MARK: Arrival

    /// The landing of a face's pop: the hop's tiny squash (`Theme.hopSquashScaleX` / `hopSquashScaleY`),
    /// reached and released within `Theme.hopSquashDuration`, starting at `begin` (layer time).
    /// Additive, so it rides on the pop's spring instead of replacing it.
    static func landingSquash(begin: CFTimeInterval) -> CAAnimationGroup {
        let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scaleX.values = [0.0, Theme.hopSquashScaleX - 1, 0.0]
        let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        scaleY.values = [0.0, Theme.hopSquashScaleY - 1, 0.0]
        for scale in [scaleX, scaleY] {
            scale.keyTimes = [0, 0.4, 1]
            scale.timingFunctions = [easeOut, easeOut]
            scale.duration = Theme.hopSquashDuration
            scale.isAdditive = true
        }
        let group = CAAnimationGroup()
        group.animations = [scaleX, scaleY]
        group.duration = Theme.hopSquashDuration
        group.beginTime = begin
        return group
    }

    // MARK: Satellites

    /// One revolution on the orbit ellipse, forever, at constant speed, starting at `phase`.
    static func orbit(size: CGFloat, phase: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = BlobSatelliteLayout.orbitPath(size: size)
        animation.calculationMode = .paced
        animation.rotationMode = nil
        animation.duration = Theme.satelliteOrbitPeriod
        animation.repeatCount = .infinity
        animation.timeOffset = phase * Theme.satelliteOrbitPeriod
        return animation
    }

    /// A slight vertical bob on top of the orbit (additive), phase shifted per satellite.
    static func bob(size: CGFloat, phase: Double) -> CAKeyframeAnimation {
        let amplitude = size * Theme.satelliteBobAmplitude
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, amplitude, 0, -amplitude, 0]
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        animation.duration = Theme.satelliteBobPeriod
        animation.repeatCount = .infinity
        animation.timeOffset = phase * Theme.satelliteBobPeriod
        animation.isAdditive = true
        return animation
    }

    /// A satellite arriving: scale from `Theme.satelliteEnterScale` and fade in, ease-out; `begin`
    /// (layer time) holds it hidden until then (a face that has not popped in yet).
    static func satelliteEnter(begin: CFTimeInterval? = nil) -> CAAnimationGroup {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = Theme.satelliteOpacity
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = Theme.satelliteEnterScale
        scale.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = Theme.satelliteEnterDuration
        group.timingFunction = easeOut
        if let begin {
            group.beginTime = begin
            group.fillMode = .backwards
        }
        return group
    }

    /// A satellite leaving: a fade to nothing, kept at the end (the layer is removed afterwards).
    static func satelliteExit(fromOpacity: Any?) -> CABasicAnimation {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = 0
        opacity.duration = Theme.satelliteExitDuration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false
        return opacity
    }
}
