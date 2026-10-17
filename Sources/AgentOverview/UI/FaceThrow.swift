import QuartzCore

/// What a press on the panel turns into, decided once per press from its first movement past a
/// threshold (`decide`): a throw of the face out of the capsule, a drag of the panel along the
/// edge, or (until either threshold is passed) still a plain click.
enum PressAxis: Equatable, Sendable {
    /// Not past either threshold yet: the release is a plain click.
    case click
    /// Vertical first: the panel moves along the screen edge (`PanelDragController`, as before).
    case dragPanel
    /// Away from the screen edge first (leftward on the right edge), on a session face: the face
    /// follows the pointer and can be thrown out.
    case throwFace

    /// The axis of a press whose pointer moved `dx`, `dy` (screen points, any y direction) since it
    /// went down. More than `dragThreshold` vertically is a panel drag, more than `throwThreshold`
    /// away from the screen edge of `side` (to the left on the right edge, to the right on the left
    /// edge) is a throw when the press is on a session face (`canThrow`). Both at once (one fast
    /// event): the larger travel wins, a tie goes to the throw. Travel toward the edge alone never
    /// decides anything; it stays a click until it turns vertical.
    static func decide(
        dx: CGFloat, dy: CGFloat, canThrow: Bool, side: PanelSide = .default,
        throwThreshold: CGFloat = Theme.throwThreshold, dragThreshold: CGFloat = Theme.dragThreshold
    ) -> PressAxis {
        let vertical = PanelDragTracker.exceedsThreshold(dy: dy, threshold: dragThreshold)
        // Travel away from the edge: the canonical (right-edge) leftward travel.
        let away = -side.mirror(dx: dx)
        let outward = canThrow && away > throwThreshold
        switch (vertical, outward) {
        case (false, false): return .click
        case (true, false): return .dragPanel
        case (false, true): return .throwFace
        case (true, true): return away >= abs(dy) ? .throwFace : .dragPanel
        }
    }
}

/// Pointer velocity over the last `Theme.throwVelocityWindow`, from the event stream (no timer).
/// A sample only counts where the pointer moved; the time of the latest event (`now`) bounds the
/// window, so a pointer that rested before the release measures zero, and a release right after a
/// fast move (its event at the last drag's position) keeps the speed of that move.
struct ThrowVelocity: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        var time: TimeInterval
        var point: CGPoint
    }

    var window: TimeInterval = Theme.throwVelocityWindow
    private(set) var samples: [Sample] = []
    /// Timestamp of the latest event, moved or not.
    private(set) var now: TimeInterval = 0

    /// Adds a pointer position (screen points, y up) at an event timestamp; an unmoved pointer only
    /// advances the clock. Drops what fell out of the window.
    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        now = max(now, time)
        if samples.last?.point != point { samples.append(Sample(time: time, point: point)) }
        samples.removeAll { $0.time < now - window }
    }

    /// Points per second (screen, y up) between the oldest and newest sample in the window ending at
    /// the latest event; zero with fewer than two samples there (the pointer rested).
    var velocity: CGVector {
        let recent = samples.filter { $0.time >= now - window }
        guard let first = recent.first, let last = recent.last else { return .zero }
        let dt = last.time - first.time
        guard dt > 0.001 else { return .zero }
        return CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
    }
}

/// Where a thrown face is drawn relative to its slot, and how it gets there. Applied to the face's
/// host layer (`apply(leave:to:previous:)`), composed with a departing row's `FaceLeave`.
struct FaceThrowPose: Equatable, Sendable {
    enum Motion: Equatable, Sendable {
        /// Set at once (the face follows the pointer).
        case immediate
        /// Ease-out over `Theme.throwFlyDuration` (the fly-away, or its fade under Reduce Motion).
        case flyAway
        /// `Theme.throwReturnSpring`, the open spring (back into the slot).
        case springBack
        /// Reduce Motion: a plain ease back into the slot over `Theme.throwReduceMotionReturn`.
        case easeBack
    }

    /// Offset from the slot, points, top-left coordinates (positive `dy` is down on screen).
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// Tilt in radians, positive is counterclockwise on screen (the top leans left).
    var angle: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: CGFloat = 1
    var motion: Motion = .springBack

    /// In the slot. Reached on the open spring when a held face is let go.
    static let rest = FaceThrowPose()

    /// The pose with the face at rest and no other change pending.
    var isRest: Bool { dx == 0 && dy == 0 && angle == 0 && scale == 1 && opacity == 1 }

    /// The host layer's sublayer transform for this pose and a departure scale: about the bounds'
    /// centre (`pivot`, from the layer's anchor), the offset, then the tilt, then both scales.
    /// The layers are not flipped (y up), so the top-left `dy` turns negative.
    func transform(pivot: CGPoint, leaveScale: CGFloat) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(pivot.x + dx, pivot.y - dy, 0)
        transform = CATransform3DRotate(transform, angle, 0, 0, 1)
        transform = CATransform3DScale(transform, scale * leaveScale, scale * leaveScale, 1)
        return CATransform3DTranslate(transform, -pivot.x, -pivot.y, 0)
    }

    /// Sets the throw and the departure on a face host's root layer: the transform on the sublayer
    /// transform (the root's own geometry belongs to AppKit), the opacity on the top-level sublayers.
    /// A changed pose with an animated motion animates there from what is on screen; an unchanged pose
    /// (a departure frame, any other update of the face) is set at once, and nothing at all happens
    /// while the values are already in place.
    @MainActor
    func apply(leave: FaceLeave, to root: CALayer, previous: FaceThrowPose) {
        let sublayers = root.sublayers ?? []
        let opacity = Float(leave.opacity * opacity)
        let pivot = CGPoint(x: root.bounds.width * (0.5 - root.anchorPoint.x), y: root.bounds.height * (0.5 - root.anchorPoint.y))
        let target = isRest && leave == .none ? CATransform3DIdentity : transform(pivot: pivot, leaveScale: leave.scale)
        guard !CATransform3DEqualToTransform(root.sublayerTransform, target) || sublayers.contains(where: { $0.opacity != opacity }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self != previous {
            if let make = animation {
                let from = (root.presentation() ?? root).sublayerTransform
                root.add(make("sublayerTransform", NSValue(caTransform3D: from), NSValue(caTransform3D: target)), forKey: "throw")
                for layer in sublayers {
                    let fromOpacity = (layer.presentation() ?? layer).opacity
                    if fromOpacity != opacity { layer.add(make("opacity", fromOpacity, opacity), forKey: "throw.opacity") }
                }
            } else {
                root.removeAnimation(forKey: "throw")
                for layer in sublayers { layer.removeAnimation(forKey: "throw.opacity") }
            }
        }
        root.sublayerTransform = target
        for layer in sublayers { layer.opacity = opacity }
        CATransaction.commit()
    }

    /// The animation of this pose's motion for a key path, nil for `.immediate`.
    private var animation: ((String, Any, Any) -> CAAnimation)? {
        switch motion {
        case .immediate:
            return nil
        case .flyAway:
            return { keyPath, from, to in
                let ease = CABasicAnimation(keyPath: keyPath)
                ease.fromValue = from
                ease.toValue = to
                ease.duration = Theme.throwFlyDuration
                ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
                return ease
            }
        case .springBack:
            return { keyPath, from, to in
                let spring = CASpringAnimation(keyPath: keyPath)
                let physics = Theme.throwReturnSpring
                spring.mass = physics.mass
                spring.stiffness = physics.stiffness
                spring.damping = physics.damping
                spring.initialVelocity = 0
                spring.fromValue = from
                spring.toValue = to
                spring.duration = spring.settlingDuration
                return spring
            }
        case .easeBack:
            return { keyPath, from, to in
                let ease = CABasicAnimation(keyPath: keyPath)
                ease.fromValue = from
                ease.toValue = to
                ease.duration = Theme.throwReduceMotionReturn
                ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
                return ease
            }
        }
    }
}

/// One held face, from the moment a press became a throw to its release: pure geometry, tested.
/// Horizontal follow 1:1, vertical damped by `Theme.throwVerticalFollow`, tilted with the pointer's
/// horizontal velocity (none under Reduce Motion); the release decides between out and back.
/// The rules are written for the right edge (out is to the left); on the left edge `side` mirrors
/// the horizontal travel and velocity into that frame and the fly-away back out of it, so a face is
/// thrown out to the right. The follow and the tilt (the top leans into the motion) need no mirror.
struct FaceThrow: Equatable, Sendable {
    let key: SessionKey
    /// The screen edge the panel docks to: out is away from it.
    var side: PanelSide = .default
    /// Pointer at the press, screen points (y up).
    let start: CGPoint
    /// Latest pointer, screen points (y up).
    private(set) var pointer: CGPoint
    private(set) var velocity = ThrowVelocity()

    init(key: SessionKey, start: CGPoint, at time: TimeInterval, side: PanelSide = .default) {
        self.key = key
        self.side = side
        self.start = start
        pointer = start
        velocity.add(start, at: time)
    }

    mutating func moved(to point: CGPoint, at time: TimeInterval) {
        pointer = point
        velocity.add(point, at: time)
    }

    /// The face's offset from its slot, top-left coordinates (positive `dy` is down).
    var offset: CGVector {
        CGVector(dx: pointer.x - start.x, dy: -(pointer.y - start.y) * Theme.throwVerticalFollow)
    }

    /// The face's velocity, top-left coordinates: the pointer's, vertical damped like the follow.
    var faceVelocity: CGVector {
        let v = velocity.velocity
        return CGVector(dx: v.dx, dy: -v.dy * Theme.throwVerticalFollow)
    }

    /// The tilt for a horizontal velocity: up to `Theme.throwTilt` degrees at `Theme.throwTiltVelocity`,
    /// the top leaning into the motion (moving left turns it counterclockwise).
    static func tilt(velocityX vx: CGFloat) -> CGFloat {
        let fraction = min(max(-vx / Theme.throwTiltVelocity, -1), 1)
        return fraction * Theme.throwTilt * .pi / 180
    }

    /// The pose while the pointer holds the face.
    func heldPose(reduceMotion: Bool) -> FaceThrowPose {
        let offset = offset
        return FaceThrowPose(
            dx: offset.dx, dy: offset.dy, angle: reduceMotion ? 0 : Self.tilt(velocityX: faceVelocity.dx), motion: .immediate
        )
    }

    /// Whether a face released with its centre at `faceCenterX` (canonical right-edge capsule
    /// coordinates: 0 is the capsule's inner edge, negative is beyond it, away from the screen edge)
    /// moving at `velocityX` (pt/s, canonical: negative is away from the edge) is thrown out: beyond
    /// `Theme.throwDistance`, or faster than `Theme.throwVelocity` away from the edge.
    static func removes(faceCenterX: CGFloat, velocityX: CGFloat) -> Bool {
        faceCenterX < -Theme.throwDistance || velocityX < -Theme.throwVelocity
    }

    /// The release: whether the face is thrown out, and the pose it goes to. Out: it flies on in its
    /// direction (straight away from the edge when it was not moving that way; at most 45 degrees off the horizontal) by
    /// `Theme.throwFlyDistance`, shrinking to `Theme.throwFlyScale` and fading; under Reduce Motion it
    /// only fades where it is. Back: the rest pose on the open spring (a plain ease under Reduce Motion).
    func release(reduceMotion: Bool) -> (removes: Bool, pose: FaceThrowPose) {
        let held = heldPose(reduceMotion: reduceMotion)
        // The velocity in the canonical (right-edge) frame: negative x is away from the screen edge.
        let real = faceVelocity
        let v = CGVector(dx: side.mirror(dx: real.dx), dy: real.dy)
        let removes = Self.removes(faceCenterX: Theme.capsuleWidth / 2 + side.mirror(dx: held.dx), velocityX: v.dx)
        guard removes else {
            var back = FaceThrowPose.rest
            if reduceMotion { back.motion = .easeBack }
            return (false, back)
        }
        var fly = held
        fly.opacity = 0
        fly.motion = .flyAway
        guard !reduceMotion else { return (true, fly) }
        var direction = CGVector(dx: -1, dy: 0)
        if v.dx < 0 {
            let dy = min(max(v.dy, v.dx), -v.dx)
            let length = (v.dx * v.dx + dy * dy).squareRoot()
            direction = CGVector(dx: v.dx / length, dy: dy / length)
        }
        fly.dx += side.mirror(dx: direction.dx) * Theme.throwFlyDistance
        fly.dy += direction.dy * Theme.throwFlyDistance
        fly.scale = Theme.throwFlyScale
        return (true, fly)
    }
}
