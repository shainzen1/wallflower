import AppKit
import QuartzCore

/// The Core Animation layer tree of one face and the logic that moves it between states.
///
/// Layers:
///
///     root (the view's layer)
///       magnify                    Dock-style magnification: scale and drift toward the pointer (model transform, eased by CA)
///         face                     enter animation, opacity
///         glowGroup                static, unmasked; sublayer transform = the left edge's mirror (`PanelSide.faceTransform`)
///           glowContainer          gaze translation, dart, scan, wander, breath, bounce
///             glowLeft/glowRight   shadow-only shape layers (plus a faint solid bleed)
///             glowDotLeft/Right    the same for the "!" dots
///         dotGroup                 static, masked by the screen filter image (dot grid, ascii, halftone, scanlines); the same mirror,
///                                  which leaves the mask (not a sublayer) unmirrored
///           eyeContainer           gaze translation, dart, scan, wander, breath, bounce
///             eyeLeft/eyeRight     the solid eye shapes
///             dotLeft/dotRight     the "!" dots (hidden unless needs input)
///
/// The glow sits in its own unmasked group so the dots do not cut it. The mask is on a
/// static layer so the LED lattice never moves with the eyes.
///
/// Animation keys: `pose` (spring on a state change), `gaze.x` / `gaze.y`, `color.*`, `dot.*`,
/// `loop.*` and `sched.*` (replaced on every state change), `oneshot.*`, `bounce`, `enter`, `magnify`.
@MainActor
final class EyeLayerTree {
    private let magnify = CALayer()
    private let face = CALayer()
    private let glowGroup = CALayer()
    private let glowContainer = CALayer()
    private let glowLeft = CAShapeLayer()
    private let glowRight = CAShapeLayer()
    private let glowDotLeft = CAShapeLayer()
    private let glowDotRight = CAShapeLayer()
    private let dotGroup = CALayer()
    private let dotMask = CALayer()
    private let eyeContainer = CALayer()
    private let eyeLeft = CAShapeLayer()
    private let eyeRight = CAShapeLayer()
    private let dotLeft = CAShapeLayer()
    private let dotRight = CAShapeLayer()

    private var scale: CGFloat = 2
    private var applied: FaceConfiguration?
    private var program: FaceProgram?
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// One animatable path property and which eye it shows.
    private struct PathTarget {
        let layer: CALayer
        let keyPath: String
        let mirrored: Bool
    }

    private var pathTargets: [PathTarget] {
        [
            PathTarget(layer: eyeLeft, keyPath: "path", mirrored: false),
            PathTarget(layer: eyeRight, keyPath: "path", mirrored: true),
            PathTarget(layer: glowLeft, keyPath: "path", mirrored: false),
            PathTarget(layer: glowLeft, keyPath: "shadowPath", mirrored: false),
            PathTarget(layer: glowRight, keyPath: "path", mirrored: true),
            PathTarget(layer: glowRight, keyPath: "shadowPath", mirrored: true),
        ]
    }

    private var containers: [CALayer] { [glowContainer, eyeContainer] }
    /// Glow layers of the eye bars (the pulse and the glow level apply to these and the glow dots).
    private var glowLayers: [CAShapeLayer] { [glowLeft, glowRight] }
    private var glowDotLayers: [CAShapeLayer] { [glowDotLeft, glowDotRight] }
    private var eyeLayers: [CAShapeLayer] { [eyeLeft, eyeRight] }
    private var dotLayers: [CAShapeLayer] { [dotLeft, dotRight] }
    /// Every layer carrying colour (eye fill, glow fill and shadow).
    private var coloredEyeLayers: [CAShapeLayer] { eyeLayers + dotLayers }
    private var coloredGlowLayers: [CAShapeLayer] { glowLayers + glowDotLayers }
    /// The four "!" dot layers (solid and glow), shown and hidden together.
    private var allDotLayers: [CAShapeLayer] { dotLayers + glowDotLayers }
    private var allLayers: [CALayer] {
        [magnify, face, glowGroup, glowContainer, glowLeft, glowRight, glowDotLeft, glowDotRight,
         dotGroup, dotMask, eyeContainer, eyeLeft, eyeRight, dotLeft, dotRight]
    }

    init(root: CALayer) {
        root.addSublayer(magnify)
        magnify.addSublayer(face)
        face.addSublayer(glowGroup)
        face.addSublayer(dotGroup)
        glowGroup.addSublayer(glowContainer)
        glowContainer.addSublayer(glowLeft)
        glowContainer.addSublayer(glowRight)
        glowContainer.addSublayer(glowDotLeft)
        glowContainer.addSublayer(glowDotRight)
        dotGroup.addSublayer(eyeContainer)
        eyeContainer.addSublayer(eyeLeft)
        eyeContainer.addSublayer(eyeRight)
        eyeContainer.addSublayer(dotLeft)
        eyeContainer.addSublayer(dotRight)

        for glow in coloredGlowLayers {
            glow.shadowOffset = .zero
            glow.shadowOpacity = Theme.glowOpacity
            glow.strokeColor = nil
        }
        for eye in coloredEyeLayers {
            eye.strokeColor = nil
        }
        dotMask.contentsGravity = .resize
        for layer in allLayers {
            layer.masksToBounds = false
            layer.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), "sublayers": NSNull(), "contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        }
        setDots(visible: false)
    }

    // MARK: Inputs

    /// Display scale of the window the view lives in. Shape layers rasterise at this scale.
    func setScale(_ newScale: CGFloat) {
        guard newScale > 0, newScale != scale else { return }
        scale = newScale
        for layer in allLayers {
            layer.contentsScale = scale
        }
        if let applied {
            withoutImplicitAnimation { layout(size: applied.size, filter: applied.filter) }
        }
    }

    /// Reduce Motion changed in System Settings: rebuild the current state under the new rule.
    func reduceMotionDidChange() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let applied, let program else { return }
        withoutImplicitAnimation {
            installLoops(program, size: applied.size)
        }
    }

    /// Shows a configuration, animating from whatever is on screen.
    func apply(_ config: FaceConfiguration) {
        let previous = applied
        let previousProgram = program
        let newProgram = FaceProgramBuilder.program(for: config.mode, identity: config.identity, colorMode: config.colorMode, projectKey: config.projectKey)
        applied = config
        program = newProgram

        withoutImplicitAnimation {
            let geometryChanged = previous?.size != config.size || previous?.filter != config.filter
            if geometryChanged {
                layout(size: config.size, filter: config.filter)
            }
            if previous?.side != config.side {
                // The gaze toward the screen is leftward on the right edge: mirrored on the left.
                glowGroup.sublayerTransform = config.side.faceTransform
                dotGroup.sublayerTransform = config.side.faceTransform
            }

            guard let previous, let previousProgram else {
                setModelPaths(newProgram.pose, size: config.size)
                setColors(newProgram.color)
                setGlow(newProgram.glow)
                setDots(visible: newProgram.exclamation)
                setGaze(newProgram.pose.gaze, size: config.size)
                installLoops(newProgram, size: config.size)
                setMagnify(config.magnify, animated: false)
                if let flash = newProgram.flashColor, !reduceMotion {
                    animateColors(to: newProgram.color, flash: flash)
                }
                let now = face.convertTime(CACurrentMediaTime(), from: nil)
                face.add(EyeAnimations.enter(RowEntrance.FaceTiming(delay: config.enterDelay, reduceMotion: reduceMotion), now: now), forKey: "enter")
                return
            }

            let stateChanged = previous.identity != config.identity || previous.mode != config.mode
                || previous.colorMode != config.colorMode || previous.projectKey != config.projectKey
            if stateChanged {
                transition(from: previousProgram, to: newProgram, size: config.size)
            } else if geometryChanged {
                setModelPaths(newProgram.pose, size: config.size)
                setGaze(newProgram.pose.gaze, size: config.size)
                installLoops(newProgram, size: config.size)
            }

            if previous.blinkToken != config.blinkToken {
                blinkNow(newProgram, size: config.size)
            }
            if previous.replayToken != config.replayToken {
                replay(newProgram, size: config.size)
            }
            if previous.magnify != config.magnify {
                setMagnify(config.magnify, animated: true)
            }
        }
    }

    // MARK: Magnification (hover)

    /// Sets the magnify layer's model transform; animated, it eases there from what is on screen.
    private func setMagnify(_ state: MagnifyState, animated: Bool) {
        let to = state.transform
        if animated {
            let from = (magnify.presentation() ?? magnify).transform
            magnify.add(BlobAnimations.magnify(from: from, to: to, releasing: state == .identity), forKey: "magnify")
        }
        magnify.transform = to
    }

    // MARK: State changes

    private func transition(from old: FaceProgram, to new: FaceProgram, size: CGFloat) {
        if reduceMotion {
            face.add(EyeAnimations.crossfade(), forKey: "crossfade")
            setModelPaths(new.pose, size: size)
            setColors(new.color)
            setGlow(new.glow)
            setDots(visible: new.exclamation)
            setGaze(new.pose.gaze, size: size)
            installLoops(new, size: size)
            return
        }
        if old.pose.left != new.pose.left || old.pose.right != new.pose.right {
            springPaths(to: new.pose, size: size)
        }
        if old.color != new.color || new.flashColor != nil {
            animateColors(to: new.color, flash: new.flashColor)
        }
        if old.glow != new.glow {
            // A pulsing state takes the glow over right away; otherwise ease to the new level.
            if new.pulse {
                setGlow(new.glow)
            } else {
                animateGlow(to: new.glow)
            }
        }
        if old.exclamation != new.exclamation {
            animateDots(visible: new.exclamation)
        }
        if old.pose.gaze != new.pose.gaze {
            springGaze(to: new.pose.gaze, size: size)
        }
        installLoops(new, size: size)
        if new.bounce {
            bounce()
        }
    }

    private func blinkNow(_ program: FaceProgram, size: CGFloat) {
        guard !reduceMotion else { return }
        let track = PathTrack.singleBlink(key: "oneshot.blink", open: program.pose)
        install(track, size: size)
    }

    private func replay(_ program: FaceProgram, size: CGFloat) {
        guard !reduceMotion else { return }
        if program.bounce {
            springPaths(to: program.pose, size: size)
            installLoops(program, size: size)
        }
        if let flash = program.flashColor {
            animateColors(to: program.color, flash: flash)
        }
        bounce()
    }

    // MARK: Geometry

    /// Sizes every layer. Bounds and position are set instead of `frame`, because the containers
    /// and dots carry transforms (gaze, scale) and `frame` is undefined under a non-identity transform.
    private func layout(size: CGFloat, filter: FaceFilter) {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in allLayers {
            layer.bounds = bounds
            layer.position = CGPoint(x: size / 2, y: size / 2)
            layer.contentsScale = scale
        }
        for glow in coloredGlowLayers {
            glow.shadowRadius = size * Theme.glowRadiusFraction
        }
        let dotPath = ExclamationPose.dotPath(faceSize: size)
        for (layers, mirrored) in [([dotLeft, glowDotLeft], false), ([dotRight, glowDotRight], true)] {
            let rect = ExclamationPose.dotRect(faceSize: size, mirrored: mirrored)
            for layer in layers {
                layer.bounds = CGRect(origin: .zero, size: rect.size)
                layer.position = CGPoint(x: rect.midX, y: rect.midY)
                layer.path = dotPath
            }
        }
        for glowDot in glowDotLayers {
            glowDot.shadowPath = dotPath
        }
        if let image = FaceFilterMask.image(for: filter, size: size, scale: scale) {
            dotMask.contents = image
            dotGroup.mask = dotMask
        } else {
            dotGroup.mask = nil
            dotMask.contents = nil
        }
    }

    // MARK: Paths

    private func path(for pose: FacePose, mirrored: Bool, size: CGFloat) -> CGPath {
        EyePathBuilder.path(for: mirrored ? pose.right : pose.left, faceSize: size, mirrored: mirrored)
    }

    private func setModelPaths(_ pose: FacePose, size: CGFloat) {
        for target in pathTargets {
            set(path: path(for: pose, mirrored: target.mirrored, size: size), on: target)
        }
    }

    private func set(path: CGPath, on target: PathTarget) {
        switch target.keyPath {
        case "shadowPath":
            target.layer.shadowPath = path
        default:
            (target.layer as? CAShapeLayer)?.path = path
        }
    }

    /// The path currently on screen for a target (mid-animation if one runs).
    private func currentPath(of target: PathTarget) -> CGPath? {
        let layer = target.layer.presentation() ?? target.layer
        switch target.keyPath {
        case "shadowPath":
            return layer.shadowPath
        default:
            return (layer as? CAShapeLayer)?.path
        }
    }

    private func springPaths(to pose: FacePose, size: CGFloat) {
        for target in pathTargets {
            let to = path(for: pose, mirrored: target.mirrored, size: size)
            let from = currentPath(of: target)
            set(path: to, on: target)
            target.layer.add(EyeAnimations.poseSpring(keyPath: target.keyPath, from: from, to: to), forKey: "pose")
        }
    }

    // MARK: Colours and glow

    private func setColors(_ color: EyeColor) {
        let cg = color.cgColor
        for eye in coloredEyeLayers {
            eye.fillColor = cg
        }
        for glow in coloredGlowLayers {
            glow.fillColor = cg.copy(alpha: CGFloat(Theme.glowBleedOpacity))
            glow.shadowColor = cg
        }
    }

    /// Eases every colour to `color`; with `flash` it goes there first and holds before easing on.
    private func animateColors(to color: EyeColor, flash: EyeColor?) {
        let cg = color.cgColor
        let bleed = cg.copy(alpha: CGFloat(Theme.glowBleedOpacity)) ?? cg
        let flashCG = flash?.cgColor
        let flashBleed = flashCG?.copy(alpha: CGFloat(Theme.glowBleedOpacity)) ?? flashCG
        func animation(_ keyPath: String, from: CGColor?, flash: CGColor?, to: CGColor) -> CAAnimation {
            if let flash {
                return EyeAnimations.colorFlash(keyPath: keyPath, from: from, flash: flash, to: to)
            }
            return EyeAnimations.color(keyPath: keyPath, from: from, to: to)
        }
        for eye in coloredEyeLayers {
            let from = (eye.presentation() ?? eye).fillColor
            eye.add(animation("fillColor", from: from, flash: flashCG, to: cg), forKey: "color.fill")
        }
        for glow in coloredGlowLayers {
            let current = glow.presentation() ?? glow
            glow.add(animation("fillColor", from: current.fillColor, flash: flashBleed, to: bleed), forKey: "color.fill")
            glow.add(animation("shadowColor", from: current.shadowColor, flash: flashCG, to: cg), forKey: "color.shadow")
        }
        setColors(color)
    }

    private func setGlow(_ level: Float) {
        for glow in coloredGlowLayers {
            glow.shadowOpacity = level
        }
    }

    private func animateGlow(to level: Float) {
        for glow in coloredGlowLayers {
            let from = (glow.presentation() ?? glow).shadowOpacity
            glow.add(EyeAnimations.glow(from: from, to: level), forKey: "color.glow")
        }
        setGlow(level)
    }

    // MARK: Exclamation dots

    private func setDots(visible: Bool) {
        let hidden = CGFloat(Theme.exclamationDotHiddenScale)
        for dot in allDotLayers {
            dot.opacity = visible ? 1 : 0
            dot.transform = visible ? CATransform3DIdentity : CATransform3DMakeScale(hidden, hidden, 1)
        }
    }

    /// The dots spring in a beat after the bars started their spring, and leave quickly.
    private func animateDots(visible: Bool) {
        for dot in allDotLayers {
            let animations: [(key: String, animation: CAAnimation)]
            if visible {
                let now = dot.convertTime(CACurrentMediaTime(), from: nil)
                animations = EyeAnimations.dotEnter(delay: Theme.exclamationDotStagger, now: now)
            } else {
                let current = dot.presentation() ?? dot
                animations = EyeAnimations.dotExit(
                    fromOpacity: current.opacity,
                    fromScale: current.value(forKeyPath: "transform.scale")
                )
            }
            for (key, animation) in animations {
                dot.add(animation, forKey: key)
            }
        }
        setDots(visible: visible)
    }

    // MARK: Gaze

    private func setGaze(_ gaze: GazeOffset, size: CGFloat) {
        for container in containers {
            container.transform = CATransform3DMakeTranslation(gaze.x * size, gaze.y * size, 0)
        }
    }

    private func springGaze(to gaze: GazeOffset, size: CGFloat) {
        for container in containers {
            let current = container.presentation() ?? container
            let fromX = current.value(forKeyPath: "transform.translation.x")
            let fromY = current.value(forKeyPath: "transform.translation.y")
            container.add(EyeAnimations.gazeSpring(keyPath: "transform.translation.x", from: fromX, to: gaze.x * size), forKey: "gaze.x")
            container.add(EyeAnimations.gazeSpring(keyPath: "transform.translation.y", from: fromY, to: gaze.y * size), forKey: "gaze.y")
        }
        setGaze(gaze, size: size)
    }

    // MARK: Loops

    /// Replaces every loop and scheduled animation with the program's. Under Reduce Motion nothing loops.
    private func installLoops(_ program: FaceProgram, size: CGFloat) {
        removeLoops()
        guard !reduceMotion else { return }
        for track in program.tracks {
            install(track, size: size)
        }
        let identity = applied?.identity
        if program.dart {
            let dart = EyeAnimations.dart(
                amplitude: Theme.dartAmplitude * size,
                interval: identity?.dartInterval ?? Theme.dartInterval.lowerBound,
                phase: identity?.dartPhase ?? 0
            )
            for container in containers {
                container.add(dart, forKey: "loop.dart")
            }
        }
        if program.scan {
            let scan = EyeAnimations.scan(amplitude: Theme.scanAmplitude * size, phase: identity?.scanPhase ?? 0)
            for container in containers {
                container.add(scan, forKey: "loop.scan")
            }
        }
        if program.wander {
            let wander = EyeAnimations.wander(
                radiusX: Theme.wanderRadiusX * size,
                radiusY: Theme.wanderRadiusY * size,
                phase: identity?.wanderPhase ?? 0
            )
            for container in containers {
                for (key, animation) in wander {
                    container.add(animation, forKey: key)
                }
            }
        }
        if let breath = program.breath {
            for container in containers {
                let now = container.convertTime(CACurrentMediaTime(), from: nil)
                container.add(EyeAnimations.breath(breath, phase: identity?.breathPhase ?? 0, now: now), forKey: "loop.breath")
            }
        }
        if let grow = program.grow {
            for container in containers {
                container.add(BlobAnimations.grow(grow, phase: identity?.pulsePhase ?? 0), forKey: "loop.grow")
            }
        }
        if program.pulse {
            let phase = identity?.pulsePhase ?? 0
            let radius = size * Theme.glowRadiusFraction
            for glow in coloredGlowLayers {
                glow.add(EyeAnimations.pulse(keyPath: "shadowOpacity", from: program.glow, to: Theme.pulseGlowOpacity, phase: phase), forKey: "loop.pulse.opacity")
                glow.add(EyeAnimations.pulse(keyPath: "shadowRadius", from: radius, to: radius * Theme.pulseGlowRadiusFactor, phase: phase), forKey: "loop.pulse.radius")
            }
            for eye in eyeLayers {
                eye.add(EyeAnimations.pulse(keyPath: "opacity", from: 1.0, to: Theme.pulseEyeOpacity, phase: phase), forKey: "loop.pulse.eye")
            }
        }
        // A pose spring still in flight must stay on top of the freshly installed loops.
        if eyeLeft.animation(forKey: "pose") != nil {
            springPaths(to: program.pose, size: size)
        }
    }

    private func install(_ track: PathTrack, size: CGFloat) {
        for target in pathTargets {
            let now = target.layer.convertTime(CACurrentMediaTime(), from: nil)
            let animation = EyeAnimations.animation(for: track, keyPath: target.keyPath, now: now) { pose in
                self.path(for: pose, mirrored: target.mirrored, size: size)
            }
            target.layer.add(animation, forKey: track.key)
        }
    }

    private func removeLoops() {
        for layer in allLayers {
            for key in layer.animationKeys() ?? [] where EyeAnimations.loopPrefixes.contains(where: { key.hasPrefix($0) }) {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    private func bounce() {
        for container in containers {
            container.add(EyeAnimations.bounce(), forKey: "bounce")
        }
    }

    // MARK: Helpers

    private func withoutImplicitAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
