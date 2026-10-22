import Foundation

/// Maps a face mode (status or explicit expression) and an identity to a `FaceProgram`.
/// This is the status table from the brief in code: expression, colour, gaze and loops.
enum FaceProgramBuilder {
    static func program(
        for mode: FaceMode,
        identity: FaceIdentity,
        colorMode: Theme.ColorMode = Theme.colorMode,
        projectKey: String? = nil,
        now: Date = Date()
    ) -> FaceProgram {
        switch mode {
        case .expression(let expression):
            return FaceProgram(pose: resolved(expression, identity), color: restingColor(identity, colorMode: colorMode, projectKey: projectKey))
        case .action(let face):
            return actionProgram(face, identity: identity)
        case .status(let status):
            return program(for: status, identity: identity, colorMode: colorMode, projectKey: projectKey, now: now)
        }
    }

    // MARK: Colour

    /// Colour of a face shown outside any status (playground expressions): idle grey in `.status`
    /// mode, the seeded palette colour in `.identity` mode, the project colour in `.project` mode.
    static func restingColor(_ identity: FaceIdentity, colorMode: Theme.ColorMode = Theme.colorMode, projectKey: String? = nil) -> EyeColor {
        switch colorMode {
        case .status: Theme.idleColor
        case .identity: identity.color
        case .project: projectKey.map(ProjectColor.color(for:)) ?? Theme.idleColor
        }
    }

    /// The resting colour of a status. Needs input is amber and your turn `Theme.yourTurnColor` in every
    /// mode; `.project` mode without a project key falls back to the status colours.
    static func color(for status: FaceStatus, identity: FaceIdentity, colorMode: Theme.ColorMode = Theme.colorMode, projectKey: String? = nil) -> EyeColor {
        if case .project = colorMode, let projectKey {
            return ProjectColor.color(for: status, projectKey: projectKey)
        }
        switch (colorMode, status) {
        case (_, .needsInput): return Theme.needsInputColor
        case (_, .yourTurn): return Theme.yourTurnColor
        case (.identity, _): return identity.color
        case (_, .working): return Theme.workingColor
        case (_, .idle): return Theme.idleColor
        case (_, .justFinished): return Theme.idleColor
        case (_, .ended): return Theme.endedColor
        }
    }

    /// Glow strength of a status. In `.identity` mode every status glows the same, as before.
    static func glow(for status: FaceStatus, colorMode: Theme.ColorMode = Theme.colorMode) -> Float {
        guard colorMode != .identity else { return Theme.glowOpacity }
        switch status {
        case .idle: return Theme.idleGlowOpacity
        case .ended: return Theme.endedGlowOpacity
        case .needsInput, .working, .justFinished, .yourTurn: return Theme.glowOpacity
        }
    }

    // MARK: Status programs

    /// An action face in the dot-matrix style: sleepy at rest, normal when hovered, focused while launching.
    static func actionProgram(_ face: ActionFace, identity: FaceIdentity) -> FaceProgram {
        let expression: Expression = switch face.phase {
        case .resting: .sleepy
        case .hovered: .normal
        case .launching: .focused
        }
        let pose = resolved(expression, identity)
        var program = FaceProgram(pose: pose, color: face.color, glow: Theme.idleGlowOpacity)
        let interval = identity.blinkInterval(in: face.phase == .resting ? Theme.sleepyBlinkInterval : Theme.idleBlinkInterval)
        program.tracks = [.blink(key: "loop.blink", open: pose, interval: interval, phase: identity.blinkPhase)]
        if face.phase == .launching {
            program.breath = BreathLoop(scale: Theme.workingBreathScale, period: Theme.workingBreathPeriod)
        }
        return program
    }

    private static func program(for status: FaceStatus, identity: FaceIdentity, colorMode: Theme.ColorMode, projectKey: String?, now: Date) -> FaceProgram {
        let color = color(for: status, identity: identity, colorMode: colorMode, projectKey: projectKey)
        let glow = glow(for: status, colorMode: colorMode)

        switch status {
        case .needsInput:
            let exclamation = Theme.needsInputStyle == .exclamation
            let base = exclamation
                ? ExclamationPose.pose
                : resolved(identity.pick(.surprised, .awe, slot: 40), identity)
            let pose = base
                .looking(Theme.needsInputGaze)
                .tinted(Theme.needsInputColor)
            var program = FaceProgram(pose: pose, color: color, glow: glow)
            program.exclamation = exclamation
            program.tracks = [
                .blink(
                    key: "loop.blink",
                    open: pose,
                    interval: identity.blinkInterval(in: Theme.needsInputBlinkInterval),
                    phase: identity.blinkPhase,
                    doubleEvery: Theme.needsInputDoubleBlinkEvery
                ),
            ]
            program.pulse = true
            program.grow = Theme.attentionGrow
            return program

        case .working:
            let focused = resolved(.focused, identity)
            var program = FaceProgram(pose: focused, color: color, glow: glow)
            program.tracks = [workingTrack(focused: focused, identity: identity)]
            program.dart = true
            program.scan = true
            program.breath = BreathLoop(scale: Theme.workingBreathScale, period: Theme.workingBreathPeriod)
            return program

        case .yourTurn(let since):
            // The idle program in the your-turn colour at the full glow (it never reaches sleepy:
            // `Theme.sleepyAfter` is longer than `Theme.yourTurnFor`).
            var program = Self.program(for: .idle(since: since), identity: identity, colorMode: colorMode, projectKey: projectKey, now: now)
            program.color = color
            program.glow = glow
            return program

        case .idle(let since):
            let normal = resolved(.normal, identity)
            let sleepy = resolved(.sleepy, identity)
            let elapsed = now.timeIntervalSince(since)
            let remaining = Theme.sleepyAfter - elapsed
            let sleepyInterval = identity.blinkInterval(in: Theme.sleepyBlinkInterval)
            var program = FaceProgram(pose: remaining <= 0 ? sleepy : normal, color: color, glow: glow)
            program.wander = true
            program.breath = BreathLoop(scale: Theme.idleBreathScale, period: Theme.idleBreathPeriod)
            if remaining <= 0 {
                program.tracks = [
                    .blink(key: "loop.blinkSleepy", open: sleepy, interval: sleepyInterval, phase: identity.blinkPhase),
                ]
                return program
            }
            program.tracks = [
                idleTrack(normal: normal, identity: identity),
                .move(
                    key: "sched.drift",
                    from: normal, to: sleepy,
                    after: remaining, duration: Theme.sleepyDriftDuration, transition: .ease
                ),
                .blink(
                    key: "loop.blinkSleepy",
                    open: sleepy,
                    interval: sleepyInterval,
                    phase: identity.blinkPhase,
                    delay: remaining + Theme.sleepyDriftDuration
                ),
            ]
            return program

        case .justFinished:
            let happy = resolved(identity.pick(.happy, .glee, slot: 41), identity)
            let normal = resolved(.normal, identity)
            var program = FaceProgram(pose: happy, color: color, glow: glow)
            if colorMode == .status || (colorMode == .project && projectKey != nil) {
                program.flashColor = Theme.justFinishedColor
            }
            let settle = EyeAnimations.poseSpringSettlingDuration
            program.tracks = [
                .move(
                    key: "sched.return",
                    from: happy, to: normal,
                    after: Theme.justFinishedHold, duration: settle, transition: .spring
                ),
                .blink(
                    key: "loop.blink",
                    open: normal,
                    interval: identity.blinkInterval(in: Theme.idleBlinkInterval),
                    phase: identity.blinkPhase,
                    delay: Theme.justFinishedHold + settle,
                    doubleEvery: Theme.idleDoubleBlinkEvery
                ),
            ]
            program.bounce = true
            program.wander = true
            program.breath = BreathLoop(scale: Theme.idleBreathScale, period: Theme.idleBreathPeriod, delay: Theme.bounceDuration)
            return program

        case .ended:
            let closed = resolved(.normal, identity).closed()
            return FaceProgram(pose: closed, color: color, glow: glow)
        }
    }

    // MARK: Tracks

    /// The working loop: focused with a blink in the middle, a squint or skeptic for a while,
    /// focused again (a little longer, no blink), the other alternative, and round again.
    /// The focused stretch length and the order come from the seed.
    private static func workingTrack(focused: FacePose, identity: FaceIdentity) -> PathTrack {
        let stretch = identity.workingPoseInterval
        let edge = Theme.blinkEdgeDuration
        let hold = Theme.blinkHoldDuration
        let swap = Theme.varietyTransitionDuration
        let alternatives = identity.workingAlternatives.map { resolved($0, identity) }
        let closed = focused.closed()
        let steps: [PathTrack.Step] = [
            .init(pose: focused, hold: stretch * 0.5 - edge, transition: edge),
            .init(pose: closed, hold: hold, transition: edge),
            .init(pose: focused, hold: stretch * 0.5 - edge - hold - swap, transition: swap),
            .init(pose: alternatives[0], hold: Theme.varietyHoldDuration, transition: swap),
            .init(pose: focused, hold: stretch * 1.15 - swap, transition: swap),
            .init(pose: alternatives[1], hold: Theme.varietyHoldDuration, transition: swap),
        ]
        return PathTrack(key: "loop.variety", steps: steps, repeats: true, phase: identity.varietyPhase)
    }

    /// The idle loop: slow blinks (every n-th a double blink) for about one mood interval,
    /// then a one second mood flicker (happy or skeptic, by seed), and round again.
    private static func idleTrack(normal: FacePose, identity: FaceIdentity) -> PathTrack {
        let blinkInterval = identity.blinkInterval(in: Theme.idleBlinkInterval)
        let moodInterval = identity.idleMoodInterval
        let moodTransition = Theme.idleMoodTransitionDuration
        let moodCost = moodTransition * 2 + Theme.idleMoodHold
        let mood = resolved(identity.idleMood, identity)
        var steps: [PathTrack.Step] = []
        var elapsed: TimeInterval = 0
        var cycle = 0
        while elapsed + blinkInterval + moodCost <= moodInterval {
            let double = (cycle + 1) % Theme.idleDoubleBlinkEvery == 0
            steps += PathTrack.blinkCycle(open: normal, interval: blinkInterval, double: double)
            elapsed += blinkInterval
            cycle += 1
        }
        let rest = max(moodInterval - elapsed - moodCost, 0.5)
        steps.append(.init(pose: normal, hold: rest, transition: moodTransition))
        steps.append(.init(pose: mood, hold: Theme.idleMoodHold, transition: moodTransition))
        return PathTrack(key: "loop.idle", steps: steps, repeats: true, phase: identity.blinkPhase)
    }

    /// Expression pose with the identity's preset applied.
    static func resolved(_ expression: Expression, _ identity: FaceIdentity) -> FacePose {
        expression.pose.applying(identity.preset)
    }
}
