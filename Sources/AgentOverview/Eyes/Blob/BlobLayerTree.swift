import AppKit
import QuartzCore

/// The Core Animation layer tree of one blob face and the logic that moves it between states.
///
/// Layers:
///
///     root (the view's layer)
///       haloClip               the row's cell (capsule width by row pitch, masksToBounds): no glow ever leaves it
///         haloFollow           the magnification's drift only (translation), so the glow follows the face but never scales
///           haloHost           fade in and out of the glow, to the halo's peak opacity; the same mirror as `face`; the lift
///                              of every hop (the your-turn hop's `loop.haloLift`, the attention hop's `oneshot.hopLift`),
///                              so the glow rises and lands with the body, inside the clip
///             halo             the shaped glow (`BlobHalo`): a shadow of the body's silhouette scaled up (`shadowPath`, no fill),
///                              morphing with the body; its opacity loop relative to the peak (waiting: amber, in step with
///                              the grow; done: mint, breathing; your turn: the body colour, breathing, swelling with each hop)
///       burstClip              the capsule's width (masksToBounds), tall: the burst never leaves the capsule sideways
///         burstMagnify         the same transform as `magnify`
///           burst dot*         the done burst, short-lived shape layers removed when their flight is over
///       magnify                Dock-style magnification: scale and drift toward the pointer (model transform, eased by CA)
///         satellite*           subagent satellites (below the face): orbit on `position`, bob, enter and exit
///         face                 enter animation, attention hop, opacity; mask = the screen filter image (static, so the lattice never moves);
///                              sublayer transform = the left edge's mirror (`PanelSide.faceTransform`, identity on the right)
///           genie              the hover stretch (`.stretch` effect): leftward shift (rightward when mirrored) and vertical squeeze (springs)
///             scaler           rest scale (waiting faces are bigger, 1 while hovered under magnify), body pulse, breath, bounce, grow (transform.scale),
///                              the your-turn hop (additive translation and squash)
///               body           the silhouette, one shape layer (path morphs, the your-turn swap, the genie stretch, fill colour = status)
///               eyeGroup       mask = bodyMask (the same path as the body, animated in step)
///                 eyeLeft/Right  capsule holes, path keyframes (blinks, gaze, expressions), opacity pulse (running), genie lean
///
/// Animation keys: `oneshot.transition` (the blink that hides a state change), `morph` (body path),
/// `color.fill`, `loop.*` and `sched.*` (replaced on every state change), `oneshot.blink`, `oneshot.hop`,
/// `bounce`, `enter` + `enter.squash` + `oneshot.enterEyes` (the arrival pop, `RowEntrance`), `genie.*` (the hover
/// springs), `magnify` (the eased magnification), `halo.fade`, `halo.color` + `oneshot.glide` (done easing
/// into your turn), `rest.scale`, `loop.swap` + `loop.bounce` + `loop.haloSwell` + `loop.haloLift` (the
/// your-turn swap, hop, glow swell and glow lift) and `swap.settle` + `swap.settleBounce` + `swap.settleSwell`
/// (their ease back to rest when paused or replaced; the glow's host settles its lift under `swap.settleBounce`
/// too), `oneshot.hopLift` (the glow lifting with the attention hop), `oneshot.excited` (eyes and face) +
/// `oneshot.excitedLift` + `oneshot.excitedWiggle` (the excited reaction; its brighten replaces `color.fill`). The halo runs `morph`, `loop.swap`,
/// `swap.settle` and `sched.body` on its `shadowPath`.
@MainActor
final class BlobLayerTree {
    private let root: CALayer
    private let haloClip = CALayer()
    private let haloFollow = CALayer()
    private let burstClip = CALayer()
    private let burstMagnify = CALayer()
    private let magnify = CALayer()
    private let face = CALayer()
    private let filterMask = CALayer()
    private let genie = CALayer()
    private let scaler = CALayer()
    private let body = CAShapeLayer()
    private let eyeGroup = CALayer()
    private let bodyMask = CAShapeLayer()
    private let eyeLeft = CAShapeLayer()
    private let eyeRight = CAShapeLayer()
    private let haloHost = CALayer()
    private let halo = CAShapeLayer()
    /// Subagent satellites on screen, in order of arrival. Each keeps its own phase.
    private var satellites: [BlobSatellite] = []

    private var scale: CGFloat = 2
    private var applied: FaceConfiguration?
    private var program: BlobProgram?
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// The genie stretch is on (the row is hovered): every body path is the stretched one.
    private var hovered = false
    /// The hover took the attention scale over (a waiting face hovered under magnify): the rest scale
    /// is 1 and the grow loop is paused, so the magnification alone sizes the face.
    private var attentionTakeover = false
    /// The hover paused the your-turn swap and hop (any hovered face that has them): the face rests
    /// under the pointer and picks the loop up again after the hover.
    private var swapPaused = false
    /// When the blink of the last state change is over (media time), so the excited reaction can
    /// start as the lids open on the new state. Nil before any blinked change.
    private var transitionEnd: CFTimeInterval?

    private var eyeLayers: [CAShapeLayer] { [eyeLeft, eyeRight] }
    private var bodyLayers: [CAShapeLayer] { [body, bodyMask] }
    /// The key path the halo's silhouette lives on: the glow is the shadow of the scaled silhouette
    /// (a shadow from `shadowPath` costs the render server nothing measurable; a Gaussian blur filter on
    /// a filled path looked the same and cost WindowServer about 5 % of a core with four lit faces).
    private static let haloPathKey = "shadowPath"
    private var allLayers: [CALayer] {
        [haloClip, haloFollow, burstClip, burstMagnify, magnify, face, filterMask, genie, scaler, body, eyeGroup, bodyMask, eyeLeft, eyeRight, haloHost, halo]
    }
    /// The layers sized to the face square and centred in their superlayer (the clips and the halo have their own bounds).
    private var faceLayers: [CALayer] { [magnify, face, filterMask, genie, scaler, body, eyeGroup, bodyMask, eyeLeft, eyeRight] }

    init(root: CALayer) {
        self.root = root
        root.addSublayer(haloClip)
        haloClip.addSublayer(haloFollow)
        haloFollow.addSublayer(haloHost)
        haloHost.addSublayer(halo)
        root.addSublayer(burstClip)
        burstClip.addSublayer(burstMagnify)
        root.addSublayer(magnify)
        magnify.addSublayer(face)
        face.addSublayer(genie)
        genie.addSublayer(scaler)
        scaler.addSublayer(body)
        scaler.addSublayer(eyeGroup)
        eyeGroup.addSublayer(eyeLeft)
        eyeGroup.addSublayer(eyeRight)
        eyeGroup.mask = bodyMask
        bodyMask.fillColor = CGColor(gray: 1, alpha: 1)
        body.strokeColor = nil
        for eye in eyeLayers {
            eye.strokeColor = nil
            eye.fillColor = Theme.blobEyeColor.cgColor
        }
        filterMask.contentsGravity = .resize
        halo.strokeColor = nil
        halo.fillColor = nil
        halo.shadowOpacity = 1
        halo.shadowOffset = .zero
        haloHost.opacity = 0
        for layer in allLayers {
            layer.masksToBounds = false
            layer.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), "sublayers": NSNull(), "contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        }
        haloClip.masksToBounds = true
        burstClip.masksToBounds = true
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
            installLoops(program, size: applied.size, extraDelay: 0)
            for satellite in satellites {
                satellite.installMotion(size: applied.size, reduceMotion: reduceMotion)
            }
        }
    }

    /// Shows a configuration, animating from whatever is on screen.
    func apply(_ config: FaceConfiguration) {
        let previous = applied
        let previousProgram = program
        let newProgram = BlobProgramBuilder.program(
            for: config.mode, identity: config.identity, bodyOverride: config.blobBody, shapeMode: config.blobShapeMode,
            activity: config.activity, colorMode: config.colorMode, projectKey: config.projectKey
        )
        applied = config
        program = newProgram
        let previousTakeover = attentionTakeover
        attentionTakeover = Self.takesOverAttention(config, program: newProgram)
        let previousSwapPaused = swapPaused
        swapPaused = Self.pausesSwap(config, program: newProgram)

        withoutImplicitAnimation {
            let geometryChanged = previous?.size != config.size || previous?.filter != config.filter
            if geometryChanged {
                layout(size: config.size, filter: config.filter)
            }
            if previous?.side != config.side {
                // The face and its glow mirror together, so the glow keeps the body's silhouette.
                face.sublayerTransform = config.side.faceTransform
                haloHost.sublayerTransform = config.side.faceTransform
            }

            guard let previous, let previousProgram else {
                hovered = config.stretched
                setGenieTransform(hovered: hovered, size: config.size)
                setMagnify(config.magnify, animated: false)
                setBody(newProgram.body, size: config.size)
                halo.shadowPath = haloPath(newProgram, size: config.size)
                setEyePaths(newProgram.pose, body: newProgram.body, size: config.size)
                setColor(newProgram.color)
                setRestScale(restScale(of: newProgram), from: nil)
                let timing = RowEntrance.FaceTiming(delay: config.enterDelay, reduceMotion: reduceMotion)
                setHalo(newProgram.halo, from: nil, delay: timing.delay)
                installLoops(newProgram, size: config.size, extraDelay: timing.end)
                if let flash = newProgram.flashColor, !reduceMotion {
                    animateColor(to: newProgram.color, flash: flash)
                }
                if newProgram.burst {
                    burst(color: newProgram.flashColor ?? newProgram.color, size: config.size)
                }
                enter(timing, program: newProgram, size: config.size)
                setSatellites(count: Self.satelliteCount(for: config), size: config.size, enterDelay: timing.delay)
                return
            }

            let activityChanged = previous.activity != config.activity && config.mode == .status(.working)
            let stateChanged = previous.identity != config.identity || previous.mode != config.mode
                || previous.blobBody != config.blobBody || previous.blobShapeMode != config.blobShapeMode || activityChanged
                || previous.colorMode != config.colorMode || previous.projectKey != config.projectKey
            if stateChanged {
                let oldRest = previousTakeover ? 1 : previousProgram.restScale
                if Self.glides(from: previous, to: config), previousProgram.body == newProgram.body, !reduceMotion {
                    glide(from: previousProgram, to: newProgram, oldRest: oldRest, size: config.size)
                } else {
                    transition(from: previousProgram, to: newProgram, oldRest: oldRest, size: config.size)
                }
            } else if previousTakeover != attentionTakeover {
                setAttentionTakeover(newProgram, from: previousTakeover ? 1 : newProgram.restScale)
            }
            if !stateChanged, previousSwapPaused != swapPaused {
                setSwapPaused(newProgram, size: config.size)
            }
            if !stateChanged && geometryChanged {
                setBody(newProgram.body, size: config.size)
                halo.shadowPath = haloPath(newProgram, size: config.size)
                setEyePaths(newProgram.pose, body: newProgram.body, size: config.size)
                installLoops(newProgram, size: config.size, extraDelay: 0)
            }

            if previous.blinkToken != config.blinkToken {
                blinkNow(newProgram, size: config.size)
            }
            if previous.replayToken != config.replayToken {
                replay(newProgram, size: config.size)
            }
            if previous.attentionToken != config.attentionToken {
                hop(size: config.size)
            }
            if previous.excitedToken != config.excitedToken, newProgram.excited {
                excite(newProgram, size: config.size)
            }
            if previous.squintToken != config.squintToken {
                squint(newProgram, size: config.size)
            }
            if previous.stretched != config.stretched {
                setGenie(hovered: config.stretched, program: newProgram, size: config.size)
            }
            if previous.magnify != config.magnify {
                setMagnify(config.magnify, animated: true)
            }
            setSatellites(count: Self.satelliteCount(for: config), size: config.size)
        }
    }

    // MARK: Magnification (hover)

    /// Sets the magnify layer's model transform; animated, it eases there from what is on screen
    /// (the follow ease after a pointer move, the release ease back to identity).
    /// The burst follows the same transform; the halo only the drift (it never scales, so it stays in its row).
    private func setMagnify(_ state: MagnifyState, animated: Bool) {
        let to = state.transform
        let drift = CATransform3DMakeTranslation(state.dx, -state.dy, 0)
        for (layer, target) in [(magnify, to), (burstMagnify, to), (haloFollow, drift)] {
            if animated {
                let from = (layer.presentation() ?? layer).transform
                layer.add(BlobAnimations.magnify(from: from, to: target, releasing: state == .identity), forKey: "magnify")
            }
            layer.transform = target
        }
    }

    // MARK: Hover takes over the attention scale

    /// Whether the hover takes the attention scale over: a face with a rest scale or a grow (waiting)
    /// whose row is hovered under the magnify effect.
    nonisolated static func takesOverAttention(_ config: FaceConfiguration, program: BlobProgram) -> Bool {
        config.hovered && config.hoverEffect == .magnify && (program.restScale != 1 || program.grow != nil)
    }

    /// The rest scale the scaler shows for `program` right now: 1 while the hover has taken over.
    private func restScale(of program: BlobProgram) -> Double {
        attentionTakeover ? 1 : program.restScale
    }

    /// The hover began or ended on a waiting face: the rest scale eases to 1 over the magnify follow
    /// (back to the attention scale over the release) and the grow loop pauses (and comes back,
    /// phase-seeded as always). The pulse and the halo keep going.
    private func setAttentionTakeover(_ program: BlobProgram, from: Double) {
        let to = restScale(of: program)
        if from != to, !reduceMotion {
            let duration = attentionTakeover ? Theme.magnifyFollowDuration : Theme.magnifyReleaseDuration
            scaler.add(BlobAnimations.restScale(from: from, to: to, duration: duration), forKey: "rest.scale")
        }
        scaler.transform = Self.restTransform(to)
        if attentionTakeover {
            scaler.removeAnimation(forKey: "loop.grow")
        } else if let grow = program.grow, !reduceMotion {
            scaler.add(BlobAnimations.grow(grow, phase: applied?.identity.pulsePhase ?? 0), forKey: "loop.grow")
        }
    }

    /// The scaler's model transform for a rest scale. z scales too: an additive `transform.scale`
    /// loop adds to the mean of the x, y and z scales, so with z left at 1 a 1.08 rest showed as 1.053
    /// as soon as the pulse ran (measured); with z in step the loops add to the rest scale itself.
    nonisolated static func restTransform(_ scale: Double) -> CATransform3D {
        CATransform3DMakeScale(scale, scale, scale)
    }

    // MARK: Hover pauses the your-turn swap

    /// Whether the hover pauses the your-turn swap and hop: a hovered face that has them, under any
    /// hover effect, so the face never hops or changes shape under the pointer.
    nonisolated static func pausesSwap(_ config: FaceConfiguration, program: BlobProgram) -> Bool {
        config.hovered && program.swap != nil
    }

    /// The hover began or ended on a your-turn face: the swap and the hop ease back to the resting body
    /// (the pointer is on it), or start again a hold after the pointer left, phase-seeded as always.
    private func setSwapPaused(_ program: BlobProgram, size: CGFloat) {
        if swapPaused {
            settleSwap()
        } else {
            installSwap(program, size: size, extraDelay: Theme.yourTurnSwapHold)
        }
    }

    /// Ends a running swap and hop without a jump: the body path and the lift ease from what is on
    /// screen to the model values. Returns the body path that was on screen (nil without a swap), so a
    /// state change can morph on from it.
    @discardableResult
    private func settleSwap() -> CGPath? {
        var onScreen: CGPath?
        for layer in bodyLayers where layer.animation(forKey: "loop.swap") != nil {
            let from = (layer.presentation() ?? layer).path
            if layer === body { onScreen = from }
            layer.removeAnimation(forKey: "loop.swap")
            if let to = layer.path {
                layer.add(BlobAnimations.swapSettle(from: from, to: to), forKey: "swap.settle")
            }
        }
        if halo.animation(forKey: "loop.swap") != nil {
            let from = (halo.presentation() ?? halo).shadowPath
            halo.removeAnimation(forKey: "loop.swap")
            if let to = halo.shadowPath {
                halo.add(BlobAnimations.swapSettle(keyPath: Self.haloPathKey, from: from, to: to), forKey: "swap.settle")
            }
        }
        if halo.animation(forKey: "loop.haloSwell") != nil {
            let swell = ((halo.presentation() ?? halo).value(forKeyPath: "transform.scale.x") as? NSNumber)?.doubleValue ?? 1
            halo.removeAnimation(forKey: "loop.haloSwell")
            if abs(swell - 1) > 0.000_1 {
                halo.add(BlobAnimations.swellSettle(from: swell - 1), forKey: "swap.settleSwell")
            }
        }
        // The body's hop and the glow's lift land the same way: from the lift on screen, on the same ease.
        for (layer, key) in [(scaler, "loop.bounce"), (haloHost, "loop.haloLift")] where layer.animation(forKey: key) != nil {
            let current = layer.presentation() ?? layer
            let lift = (current.value(forKeyPath: "transform.translation.y") as? NSNumber)?.doubleValue ?? 0
            let rest = (layer.value(forKeyPath: "transform.translation.y") as? NSNumber)?.doubleValue ?? 0
            layer.removeAnimation(forKey: key)
            if abs(lift - rest) > 0.01 {
                layer.add(BlobAnimations.bounceSettle(from: lift - rest), forKey: "swap.settleBounce")
            }
        }
        return onScreen
    }

    /// Starts the your-turn swap (body paths and the halo's) and hop (scaler, and the halo's swell and
    /// lift), `extraDelay` plus a seeded fraction of a period after `now`, all on that one clock read
    /// (building the paths between reads shifted the hop off the swap on a busy main thread). Nothing
    /// under Reduce Motion or while the hover paused it.
    private func installSwap(_ program: BlobProgram, size: CGFloat, extraDelay: TimeInterval, now: CFTimeInterval = CACurrentMediaTime()) {
        guard let swap = program.swap, !reduceMotion, !swapPaused else { return }
        let delay = extraDelay + (applied?.identity.swapPhase ?? 0) * swap.period
        if let alternate = swap.alternate {
            // Never stretched: the swap only runs while the face is not hovered (a hover that just
            // ended may still be springing back; that spring is added later and wins until it settles).
            let first = program.body.profile.path(size: size)
            let second = alternate.profile.path(size: size)
            for layer in bodyLayers {
                let begin = layer.convertTime(now, from: nil) + delay
                layer.add(BlobAnimations.shapeSwap(first: first, second: second, swap: swap, begin: begin), forKey: "loop.swap")
            }
            if program.halo != nil {
                let begin = halo.convertTime(now, from: nil) + delay
                let first = haloPath(program.body, restScale: program.restScale, size: size)
                let second = haloPath(alternate, restScale: program.restScale, size: size)
                halo.add(BlobAnimations.shapeSwap(keyPath: Self.haloPathKey, first: first, second: second, swap: swap, begin: begin), forKey: "loop.swap")
            }
        }
        let begin = scaler.convertTime(now, from: nil) + delay
        scaler.add(BlobAnimations.swapBounce(swap, size: size, begin: begin), forKey: "loop.bounce")
        if program.halo != nil {
            let haloBegin = halo.convertTime(now, from: nil) + delay
            halo.add(BlobAnimations.haloSwell(swap, begin: haloBegin), forKey: "loop.haloSwell")
            // The glow rises and lands with the body: the hop's lift on the host (the swell stays on the
            // glow itself, so it still scales about the face centre), the squash only on the body.
            haloHost.add(BlobAnimations.swapLift(swap, size: size, begin: begin), forKey: "loop.haloLift")
        }
    }

    // MARK: Genie stretch (hover)

    /// The hover began or ended: the body path springs to the stretched (or resting) silhouette,
    /// the genie layer shifts left and squeezes (or returns), the eyes lean toward the pointer. The
    /// stretch spring overshoots, the exit spring is tighter; Reduce Motion eases. Loops keep running.
    private func setGenie(hovered: Bool, program: BlobProgram, size: CGFloat) {
        self.hovered = hovered
        let entering = hovered
        let to = bodyPath(program.body, size: size)
        for layer in bodyLayers {
            let from = (layer.presentation() ?? layer).path
            layer.add(BlobAnimations.genie(keyPath: "path", from: from, to: to, entering: entering, reduceMotion: reduceMotion), forKey: "genie.path")
            layer.path = to
        }
        let pose = Self.geniePose(hovered: hovered, size: size)
        let current = genie.presentation() ?? genie
        genie.add(BlobAnimations.genie(keyPath: "transform.translation.x", from: current.value(forKeyPath: "transform.translation.x"), to: pose.shift, entering: entering, reduceMotion: reduceMotion), forKey: "genie.shift")
        genie.add(BlobAnimations.genie(keyPath: "transform.scale.y", from: current.value(forKeyPath: "transform.scale.y"), to: pose.squeeze, entering: entering, reduceMotion: reduceMotion), forKey: "genie.squeeze")
        for eye in eyeLayers {
            let eyeCurrent = eye.presentation() ?? eye
            eye.add(BlobAnimations.genie(keyPath: "transform.translation.x", from: eyeCurrent.value(forKeyPath: "transform.translation.x"), to: pose.lean, entering: entering, reduceMotion: reduceMotion), forKey: "genie.lean")
        }
        setGenieTransform(hovered: hovered, size: size)
    }

    /// The model transforms of the genie pose (no animation).
    private func setGenieTransform(hovered: Bool, size: CGFloat) {
        let pose = Self.geniePose(hovered: hovered, size: size)
        genie.transform = CATransform3DScale(CATransform3DMakeTranslation(pose.shift, 0, 0), 1, pose.squeeze, 1)
        for eye in eyeLayers {
            eye.transform = CATransform3DMakeTranslation(pose.lean, 0, 0)
        }
    }

    /// Shift, squeeze and eye lean of the genie pose for a face of `size` (all zero or one at rest).
    nonisolated static func geniePose(hovered: Bool, size: CGFloat) -> (shift: CGFloat, squeeze: CGFloat, lean: CGFloat) {
        guard hovered else { return (0, 1, 0) }
        return (-size * Theme.genieShift, Theme.genieSqueeze, -size * Theme.genieEyeLean)
    }

    /// The body path for the current hover state: stretched toward the bulge while hovered.
    private func bodyPath(_ body: BlobBody, size: CGFloat) -> CGPath {
        (hovered ? BlobGenie.stretched(body.profile) : body.profile).path(size: size)
    }

    // MARK: Halo and rest scale

    /// Shows (or hides) the glow behind the face: its colour, its resting level (what Reduce Motion
    /// shows steadily), a fade of the host from what is on screen to the halo's peak opacity; the
    /// pulse loops (relative to the peak) come with `installLoops`.
    private func setHalo(_ newHalo: BlobHalo?, from: BlobHalo?, delay: TimeInterval = 0) {
        if let newHalo {
            halo.shadowColor = newHalo.color.cgColor
            halo.opacity = Float(newHalo.restFraction)
        }
        let to = newHalo?.opacity ?? 0
        let current = (haloHost.presentation() ?? haloHost).opacity
        if from != nil || newHalo != nil {
            let fade = BlobAnimations.haloFade(from: current, to: to)
            if delay > 0 {
                // A face that has not popped in yet: the glow waits for it.
                fade.beginTime = haloHost.convertTime(CACurrentMediaTime(), from: nil) + delay
                fade.fillMode = .backwards
            }
            haloHost.add(fade, forKey: "halo.fade")
        }
        haloHost.opacity = Float(to)
    }

    /// A halo changing in place (done to your turn): the colour cross-fades and the host eases to the
    /// new peak; a halo that starts or ends fades like any other.
    private func crossfadeHalo(_ newHalo: BlobHalo?, from old: BlobHalo?) {
        guard let newHalo, old != nil else {
            setHalo(newHalo, from: old)
            return
        }
        let color = newHalo.color.cgColor
        let animation = CABasicAnimation(keyPath: "shadowColor")
        animation.fromValue = (halo.presentation() ?? halo).shadowColor
        animation.toValue = color
        animation.duration = Theme.haloFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.add(animation, forKey: "halo.color")
        halo.shadowColor = color
        halo.opacity = Float(newHalo.restFraction)
        let current = (haloHost.presentation() ?? haloHost).opacity
        haloHost.add(BlobAnimations.haloFade(from: current, to: newHalo.opacity), forKey: "halo.fade")
        haloHost.opacity = Float(newHalo.opacity)
    }

    /// The glow's silhouette for `body` at `restScale` (never stretched: the glow stays put under the hover).
    private func haloPath(_ body: BlobBody, restScale: Double, size: CGFloat) -> CGPath {
        BlobHalo.profile(for: body, restScale: restScale).path(size: size)
    }

    private func haloPath(_ program: BlobProgram, size: CGFloat) -> CGPath {
        haloPath(program.body, restScale: program.restScale, size: size)
    }

    /// A status change: the glow takes the new silhouette, morphing from what was on screen with the
    /// body's timing when a glow was showing (`onScreen`), set at once when one fades in from nothing.
    /// Without a new halo the old silhouette stays for the fade out.
    private func morphHalo(to program: BlobProgram, from onScreen: CGPath?, size: CGFloat) {
        guard program.halo != nil else { return }
        let to = haloPath(program, size: size)
        if let onScreen, onScreen != to, !reduceMotion {
            let now = halo.convertTime(CACurrentMediaTime(), from: nil)
            halo.add(BlobAnimations.morph(keyPath: Self.haloPathKey, from: onScreen, to: to, delay: Theme.blobBlinkClose, duration: Theme.blobMorphDuration, now: now, keep: false), forKey: "morph")
        }
        halo.shadowPath = to
    }

    /// The body's rest scale (a waiting face is bigger), eased from the previous program's.
    private func setRestScale(_ restScale: Double, from: Double?) {
        if let from, from != restScale {
            scaler.add(BlobAnimations.restScale(from: from, to: restScale), forKey: "rest.scale")
        }
        scaler.transform = Self.restTransform(restScale)
    }

    // MARK: Done burst

    /// Six tiny dots fly outward from behind the body and fade; their layers go when the flight is over.
    private func burst(color: EyeColor, size: CGFloat) {
        guard !reduceMotion else { return }
        let centre = CGPoint(x: size / 2, y: size / 2)
        let path = BlobBurst.dotPath(size: size)
        var dots: [CAShapeLayer] = []
        for ray in BlobBurst.rays(size: size) {
            let dot = CAShapeLayer()
            dot.path = path
            dot.fillColor = color.cgColor
            dot.strokeColor = nil
            dot.contentsScale = scale
            dot.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), "position": NSNull(), "opacity": NSNull()]
            dot.position = CGPoint(x: centre.x + ray.start.x, y: centre.y + ray.start.y)
            dot.opacity = 0
            burstMagnify.addSublayer(dot)
            dots.append(dot)
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                for dot in dots { dot.removeFromSuperlayer() }
            }
        }
        for (dot, ray) in zip(dots, BlobBurst.rays(size: size)) {
            let now = dot.convertTime(CACurrentMediaTime(), from: nil)
            dot.add(BlobAnimations.burstDot(centre: centre, start: ray.start, end: ray.end, now: now), forKey: "burst")
        }
        CATransaction.commit()
    }

    /// Height of the burst clip in row pitches: the dots may cross into the neighbouring rows (they
    /// are gone within a moment), only the capsule's sides are hard.
    nonisolated static let burstClipRows: CGFloat = 4

    /// Satellites only orbit a working face (status mode), capped at `Theme.satelliteMax`.
    nonisolated static func satelliteCount(for config: FaceConfiguration) -> Int {
        guard config.mode == .status(.working) else { return 0 }
        return BlobSatelliteLayout.count(for: config.satellites)
    }

    // MARK: Satellites

    /// Adds or removes satellites to reach `count`. Existing ones keep their layers and phase;
    /// a newcomer takes the middle of the largest phase gap and scales in; a leaver fades out
    /// and its layer is removed when the fade is over.
    private func setSatellites(count: Int, size: CGFloat, enterDelay: TimeInterval = 0) {
        while satellites.count > count {
            let leaving = satellites.removeLast()
            let from = (leaving.layer.presentation() ?? leaving.layer).opacity
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                MainActor.assumeIsolated { leaving.layer.removeFromSuperlayer() }
            }
            leaving.layer.add(BlobAnimations.satelliteExit(fromOpacity: from), forKey: "exit")
            CATransaction.commit()
        }
        // A set that starts from nothing is spaced evenly; later arrivals fill the largest gap.
        let fresh = satellites.isEmpty ? BlobSatelliteLayout.phases(count: count) : []
        while satellites.count < count {
            let phase = satellites.count < fresh.count ? fresh[satellites.count] : BlobSatelliteLayout.nextPhase(existing: satellites.map(\.phase))
            let satellite = BlobSatellite(phase: phase)
            satellite.layer.fillColor = body.fillColor
            satellite.layout(size: size, scale: scale)
            magnify.insertSublayer(satellite.layer, below: face)
            satellite.installMotion(size: size, reduceMotion: reduceMotion)
            if !reduceMotion {
                let begin = enterDelay > 0 ? satellite.layer.convertTime(CACurrentMediaTime(), from: nil) + enterDelay : nil
                satellite.layer.add(BlobAnimations.satelliteEnter(begin: begin), forKey: "enter")
            }
            satellites.append(satellite)
        }
    }

    // MARK: Arrival

    /// The face pops in (`RowEntrance`): hidden until `timing.delay`, then it fades in and springs
    /// from `Theme.rowEnterScale` on the face layer (outside the rest scale and the loops, inside the
    /// magnification), squashes a touch on landing and arrives with closed lids that open once the
    /// spring settled. The loops start when the lids are open (`installLoops` with `timing.end`).
    /// Reduce Motion: the fade alone, eyes open.
    private func enter(_ timing: RowEntrance.FaceTiming, program: BlobProgram, size: CGFloat) {
        let now = face.convertTime(CACurrentMediaTime(), from: nil)
        face.add(EyeAnimations.enter(timing, now: now), forKey: "enter")
        guard !timing.reduceMotion else { return }
        face.add(BlobAnimations.landingSquash(begin: now + timing.landing), forKey: "enter.squash")
        install(BlobTrack.openingEyes(key: "oneshot.enterEyes", open: program.pose, opensAt: timing.eyesOpen), body: program.body, size: size)
    }

    // MARK: Attention hop

    /// One hop of the whole face (satellites stay); the glow lifts with it on the same clock (its
    /// host, no squash). Nothing under Reduce Motion. Plays the attention sound when
    /// `Theme.attentionSound` is on.
    private func hop(size: CGFloat) {
        if Theme.attentionSound {
            if let sound = NSSound(named: NSSound.Name(Theme.attentionSoundName)) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
        guard !reduceMotion else { return }
        face.add(BlobAnimations.hop(size: size), forKey: "oneshot.hop")
        haloHost.add(BlobAnimations.hopLift(size: size, additive: true), forKey: "oneshot.hopLift")
    }

    // MARK: Excited (the person's message arrived)

    /// The face perks up once: its session just started working after resting or waiting. As the
    /// blink of the state change opens (now, without one), the eyes widen and look at the person,
    /// the face hops twice (the glow lifts with it) while the body wiggles and squashes on landing,
    /// and the body brightens and eases back to its colour. The working loops wait for it and start
    /// on the pose it ends on. One-shots only: after `Theme.excitedDuration` nothing of it is left.
    /// Nothing under Reduce Motion (the state change is enough there).
    private func excite(_ program: BlobProgram, size: CGFloat) {
        guard !reduceMotion else { return }
        let now = CACurrentMediaTime()
        let wait = max(0, (transitionEnd ?? now) - now)
        installLoops(program, size: size, extraDelay: wait + Theme.excitedDuration, now: now)
        let track = BlobProgramBuilder.excitedTrack(from: program.pose, delay: wait)
        for (eye, mirrored) in [(eyeLeft, false), (eyeRight, true)] {
            // Mid-blink the track starts on the new pose as the lids open; otherwise on what is on screen.
            let onScreen = wait > 0 ? nil : (eye.presentation() ?? eye).path
            let animation = BlobAnimations.keyframes(for: track, now: eye.convertTime(now, from: nil), firstValue: onScreen) { pose in
                BlobEyes.path(for: pose, body: program.body, faceSize: size, mirrored: mirrored)
            }
            eye.add(animation, forKey: track.key)
        }
        face.add(BlobAnimations.excitedHops(size: size, begin: face.convertTime(now, from: nil) + wait), forKey: "oneshot.excited")
        haloHost.add(BlobAnimations.excitedHops(size: size, begin: haloHost.convertTime(now, from: nil) + wait), forKey: "oneshot.excitedLift")
        scaler.add(BlobAnimations.excitedWiggle(begin: scaler.convertTime(now, from: nil) + wait), forKey: "oneshot.excitedWiggle")
        let bright = program.color.brightened(Theme.excitedBrighten).cgColor
        let color = BlobAnimations.excitedColor(from: (body.presentation() ?? body).fillColor, to: program.color.cgColor, bright: bright, wait: wait)
        body.add(color, forKey: "color.fill")
        body.fillColor = program.color.cgColor
    }

    // MARK: State changes

    /// A state change hidden in a blink: the lids close on the old pose, the eyes swap while
    /// closed and open on the new pose; the body morphs and recolours as the lids are shut;
    /// the new loops begin when the blink is over, so nothing jumps.
    private func transition(from old: BlobProgram, to new: BlobProgram, oldRest: Double, size: CGFloat) {
        // A running your-turn swap hands its silhouette on screen to the morph below (the glow's too).
        let haloOnScreen = old.halo != nil ? (halo.presentation() ?? halo).shadowPath : nil
        let swapPath = settleSwap()
        removeLoops()
        setRestScale(restScale(of: new), from: oldRest)
        if old.halo != new.halo {
            setHalo(new.halo, from: old.halo)
        }
        morphHalo(to: new, from: haloOnScreen, size: size)
        if reduceMotion {
            face.add(EyeAnimations.crossfade(), forKey: "crossfade")
            setBody(new.body, size: size)
            setEyePaths(new.pose, body: new.body, size: size)
            setColor(new.color)
            installLoops(new, size: size, extraDelay: 0)
            return
        }
        let blink = BlobTrack.blinkSwap(key: "oneshot.transition", from: old.pose, to: new.pose)
        let now = CACurrentMediaTime()
        transitionEnd = now + blink.duration
        for (eye, mirrored) in [(eyeLeft, false), (eyeRight, true)] {
            let current = (eye.presentation() ?? eye).path
            let animation = BlobAnimations.keyframes(for: blink, now: eye.convertTime(now, from: nil), firstValue: current) { pose in
                BlobEyes.path(for: pose, body: new.body, faceSize: size, mirrored: mirrored)
            }
            eye.add(animation, forKey: blink.key)
            eye.path = BlobEyes.path(for: new.pose, body: new.body, faceSize: size, mirrored: mirrored)
        }
        if old.body != new.body || swapPath != nil {
            let to = bodyPath(new.body, size: size)
            for layer in bodyLayers {
                let from = swapPath ?? (layer.presentation() ?? layer).path
                layer.add(BlobAnimations.morph(from: from, to: to, delay: Theme.blobBlinkClose, duration: Theme.blobMorphDuration, now: layer.convertTime(now, from: nil), keep: false), forKey: "morph")
                layer.path = to
            }
        }
        if old.color != new.color || new.flashColor != nil {
            animateColor(to: new.color, flash: new.flashColor)
        }
        installLoops(new, size: size, extraDelay: blink.duration, now: now)
        if new.bounce {
            scaler.add(BlobAnimations.bounce(), forKey: "bounce")
        }
        if new.burst {
            burst(color: new.flashColor ?? new.color, size: size)
        }
    }

    /// Whether a status change eases without the blink: the done moment handing over to your turn
    /// (the same pill, so only the gaze, the colour and the halo move). Everything else blinks.
    nonisolated static func glides(from old: FaceConfiguration, to new: FaceConfiguration) -> Bool {
        guard case .status(.justFinished) = old.mode, case .status(.yourTurn) = new.mode else { return false }
        return old.identity == new.identity && old.blobBody == new.blobBody && old.blobShapeMode == new.blobShapeMode
            && old.colorMode == new.colorMode && old.projectKey == new.projectKey
    }

    /// The done moment easing into your turn: no blink. The eyes glide from what is on screen to the
    /// your-turn gaze over `Theme.yourTurnGlideDuration`, the colour eases from the flash, the halo
    /// cross-fades (a breath both share keeps running), and the new loops start once the eyes arrived.
    private func glide(from old: BlobProgram, to new: BlobProgram, oldRest: Double, size: CGFloat) {
        let keepsHaloLoop = Self.sharesHaloLoop(old.halo, new.halo)
        removeLoops(keepingHaloLoop: keepsHaloLoop)
        setRestScale(restScale(of: new), from: oldRest)
        crossfadeHalo(new.halo, from: old.halo)
        morphHalo(to: new, from: nil, size: size)
        let duration = Theme.yourTurnGlideDuration
        for (eye, mirrored) in [(eyeLeft, false), (eyeRight, true)] {
            let target = BlobEyes.path(for: new.pose, body: new.body, faceSize: size, mirrored: mirrored)
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = (eye.presentation() ?? eye).path
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = BlobAnimations.easeOut
            eye.add(animation, forKey: "oneshot.glide")
            eye.path = target
        }
        animateColor(to: new.color, flash: nil)
        installLoops(new, size: size, extraDelay: duration, keepingHaloLoop: keepsHaloLoop)
    }

    /// Two halos that breathe the same way (no grow): the running loop can stay through the change.
    nonisolated static func sharesHaloLoop(_ old: BlobHalo?, _ new: BlobHalo?) -> Bool {
        guard let old, let new, let breath = new.breath, old.grow == nil, new.grow == nil else { return false }
        return old.breath == breath && old.restFraction == new.restFraction
    }

    private func blinkNow(_ program: BlobProgram, size: CGFloat) {
        guard !reduceMotion else { return }
        install(.singleBlink(key: "oneshot.blink", open: program.pose), body: program.body, size: size)
    }

    /// One quick happy squint (a clicked action face), on top of whatever loop runs.
    private func squint(_ program: BlobProgram, size: CGFloat) {
        guard !reduceMotion, let identity = applied?.identity else { return }
        install(BlobProgramBuilder.squintTrack(from: program.pose, identity: identity), body: program.body, size: size)
    }

    private func replay(_ program: BlobProgram, size: CGFloat) {
        guard !reduceMotion else { return }
        if program.bounce {
            installLoops(program, size: size, extraDelay: 0)
            scaler.add(BlobAnimations.bounce(), forKey: "bounce")
        }
        if let flash = program.flashColor {
            animateColor(to: program.color, flash: flash)
        }
        if program.burst {
            burst(color: program.flashColor ?? program.color, size: size)
        }
    }

    // MARK: Geometry

    /// Sizes every layer (bounds and position, because the scaler carries a transform) and
    /// installs the screen filter as the face's static mask.
    private func layout(size: CGFloat, filter: FaceFilter) {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in faceLayers {
            layer.bounds = bounds
            layer.position = CGPoint(x: size / 2, y: size / 2)
            layer.contentsScale = scale
        }
        // The clips are the row's cell (halo) and the capsule's width (burst), in proportion to the face.
        let cell = size / Theme.faceSize
        let haloCell = CGSize(width: Theme.capsuleWidth * cell, height: Theme.rowPitch * cell)
        let burstCell = CGSize(width: Theme.capsuleWidth * cell, height: Theme.rowPitch * cell * Self.burstClipRows)
        for (clip, follower, cellSize) in [(haloClip, haloFollow, haloCell), (burstClip, burstMagnify, burstCell)] {
            clip.bounds = CGRect(origin: .zero, size: cellSize)
            clip.position = CGPoint(x: size / 2, y: size / 2)
            follower.bounds = bounds
            follower.position = CGPoint(x: cellSize.width / 2, y: cellSize.height / 2)
            for layer in [clip, follower] { layer.contentsScale = scale }
        }
        // The host and the glow are face squares centred in their superlayers (each position is in its
        // superlayer's bounds), so the glow's path shares the body's coordinates and its swell scales
        // about the face centre.
        for layer in [haloHost, halo] {
            layer.bounds = bounds
            layer.position = CGPoint(x: size / 2, y: size / 2)
            layer.contentsScale = scale
        }
        halo.shadowRadius = size * Theme.haloSoftness
        setGenieTransform(hovered: hovered, size: size)
        if let image = FaceFilterMask.image(for: filter, size: size, scale: scale) {
            filterMask.contents = image
            face.mask = filterMask
        } else {
            face.mask = nil
            filterMask.contents = nil
        }
        for satellite in satellites {
            satellite.layout(size: size, scale: scale)
            satellite.installMotion(size: size, reduceMotion: reduceMotion)
        }
    }

    // MARK: Model values

    private func setBody(_ body: BlobBody, size: CGFloat) {
        let path = bodyPath(body, size: size)
        for layer in bodyLayers {
            layer.path = path
        }
    }

    private func setEyePaths(_ pose: BlobEyePose, body: BlobBody, size: CGFloat) {
        eyeLeft.path = BlobEyes.path(for: pose, body: body, faceSize: size, mirrored: false)
        eyeRight.path = BlobEyes.path(for: pose, body: body, faceSize: size, mirrored: true)
    }

    private func setColor(_ color: EyeColor) {
        body.fillColor = color.cgColor
        for satellite in satellites {
            satellite.layer.fillColor = color.cgColor
        }
    }

    /// Eases the body colour (and the satellites') to `color`; with `flash` it goes there first and holds before easing on.
    private func animateColor(to color: EyeColor, flash: EyeColor?) {
        let from = (body.presentation() ?? body).fillColor
        let animation: CAAnimation = if let flash {
            EyeAnimations.colorFlash(keyPath: "fillColor", from: from, flash: flash.cgColor, to: color.cgColor)
        } else {
            EyeAnimations.color(keyPath: "fillColor", from: from, to: color.cgColor)
        }
        body.add(animation, forKey: "color.fill")
        for satellite in satellites {
            satellite.layer.add(animation, forKey: "color.fill")
        }
        setColor(color)
    }

    // MARK: Loops

    /// Replaces every loop and scheduled animation with the program's, all starting `extraDelay`
    /// after `now` (the blink of a transition). Under Reduce Motion nothing loops. `keepingHaloLoop`
    /// leaves a running halo breath in place (the glide into your turn). `now` is the caller's clock
    /// read, so the loops start exactly where its one-shots end however long building them took.
    private func installLoops(
        _ program: BlobProgram, size: CGFloat, extraDelay: TimeInterval, keepingHaloLoop: Bool = false,
        now: CFTimeInterval = CACurrentMediaTime()
    ) {
        settleSwap()
        removeLoops(keepingHaloLoop: keepingHaloLoop)
        guard !reduceMotion else { return }
        installSwap(program, size: size, extraDelay: extraDelay, now: now)
        for var track in program.tracks {
            track.delay += extraDelay
            install(track, body: program.body, size: size, now: now)
        }
        if let loop = program.bodyLoop {
            var delayed = loop
            delayed.delay += extraDelay
            scaler.add(EyeAnimations.breath(delayed, phase: applied?.identity.breathPhase ?? 0, now: scaler.convertTime(now, from: nil)), forKey: "loop.breath")
        }
        if let grow = program.grow, !attentionTakeover {
            scaler.add(BlobAnimations.grow(grow, phase: applied?.identity.pulsePhase ?? 0), forKey: "loop.grow")
        }
        if let haloProgram = program.halo?.unit, !keepingHaloLoop {
            let phase = applied?.identity.pulsePhase ?? 0
            if let grow = haloProgram.grow {
                halo.add(BlobAnimations.haloGrow(haloProgram, grow: grow, phase: phase), forKey: "loop.haloPulse")
            } else if let breath = haloProgram.breath {
                halo.add(BlobAnimations.haloBreath(haloProgram, breath: breath, phase: phase), forKey: "loop.haloPulse")
            }
        }
        if let scheduled = program.scheduledBody {
            let to = bodyPath(scheduled.body, size: size)
            for layer in bodyLayers {
                layer.add(BlobAnimations.morph(from: layer.path, to: to, delay: scheduled.after + extraDelay, duration: scheduled.duration, now: layer.convertTime(now, from: nil), keep: true), forKey: "sched.body")
            }
            if program.halo != nil {
                let target = haloPath(scheduled.body, restScale: program.restScale, size: size)
                halo.add(BlobAnimations.morph(keyPath: Self.haloPathKey, from: halo.shadowPath, to: target, delay: scheduled.after + extraDelay, duration: scheduled.duration, now: halo.convertTime(now, from: nil), keep: true), forKey: "sched.body")
            }
        }
        if let pulse = program.eyePulse {
            for eye in eyeLayers {
                eye.add(BlobAnimations.eyePulse(pulse, delay: extraDelay, now: eye.convertTime(now, from: nil)), forKey: "loop.eyeOpacity")
            }
        }
    }

    private func install(_ track: BlobTrack, body: BlobBody, size: CGFloat, now: CFTimeInterval = CACurrentMediaTime()) {
        for (eye, mirrored) in [(eyeLeft, false), (eyeRight, true)] {
            let animation = BlobAnimations.keyframes(for: track, now: eye.convertTime(now, from: nil)) { pose in
                BlobEyes.path(for: pose, body: body, faceSize: size, mirrored: mirrored)
            }
            eye.add(animation, forKey: track.key)
        }
    }

    private func removeLoops(keepingHaloLoop: Bool = false) {
        for layer in allLayers {
            for key in layer.animationKeys() ?? [] where BlobAnimations.loopPrefixes.contains(where: { key.hasPrefix($0) }) {
                if keepingHaloLoop, layer === halo, key == "loop.haloPulse" { continue }
                layer.removeAnimation(forKey: key)
            }
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
