import Foundation

/// Maps a face mode (status or explicit expression) and an identity to a `BlobProgram`:
/// the status table for the blob style, in code. Shape, colour, gaze and loops per status.
enum BlobProgramBuilder {
    static func program(
        for mode: FaceMode,
        identity: FaceIdentity,
        bodyOverride: BlobBody? = nil,
        shapeMode: Theme.BlobShapeMode = Theme.blobShapeMode,
        activity: SessionActivity = .thinking,
        colorMode: Theme.ColorMode = Theme.colorMode,
        projectKey: String? = nil,
        now: Date = Date()
    ) -> BlobProgram {
        switch mode {
        case .expression(let expression):
            let body = bodyOverride ?? restingBody(identity, shapeMode: shapeMode)
            return BlobProgram(pose: resolved(expression, identity), body: body, color: restingColor(identity, colorMode: colorMode, projectKey: projectKey))
        case .action(let face):
            return actionProgram(face, identity: identity, bodyOverride: bodyOverride)
        case .status(let status):
            return program(for: status, identity: identity, bodyOverride: bodyOverride, shapeMode: shapeMode, activity: activity, colorMode: colorMode, projectKey: projectKey, now: now)
        }
    }

    // MARK: Colour and body

    /// Body colour outside any status (playground expressions): idle grey in `.status` colour
    /// mode, the seeded palette colour in `.identity` mode, the project colour in `.project` mode.
    static func restingColor(_ identity: FaceIdentity, colorMode: Theme.ColorMode = Theme.colorMode, projectKey: String? = nil) -> EyeColor {
        switch colorMode {
        case .status: Theme.idleColor
        case .identity: identity.blobColor
        case .project: projectKey.map(ProjectColor.color(for:)) ?? Theme.idleColor
        }
    }

    /// Body colour of a status. Needs input is amber and your turn `Theme.yourTurnColor` in every colour
    /// mode. `.project` mode without a project key (nothing to hash) falls back to the status colours.
    static func color(for status: FaceStatus, identity: FaceIdentity, colorMode: Theme.ColorMode = Theme.colorMode, projectKey: String? = nil) -> EyeColor {
        if case .project = colorMode, let projectKey {
            return ProjectColor.color(for: status, projectKey: projectKey)
        }
        switch (colorMode, status) {
        case (_, .needsInput): return Theme.needsInputColor
        case (_, .yourTurn): return Theme.yourTurnColor
        case (.identity, _): return identity.blobColor
        case (_, .working): return Theme.workingColor
        case (_, .idle): return Theme.idleColor
        case (_, .justFinished): return Theme.idleColor
        case (_, .ended): return Theme.endedColor
        }
    }

    /// Body outside any status: the idle capsule in `.status` shape mode, the seed's silhouette otherwise.
    static func restingBody(_ identity: FaceIdentity, shapeMode: Theme.BlobShapeMode) -> BlobBody {
        shapeMode == .status ? BlobBody(shape: Theme.blobIdleShape) : BlobBody(shape: identity.shape)
    }

    /// Body of a status: the status shape in `.status` mode, the seed's silhouette in `.identity`
    /// mode (which still sags when sleepy but never flattens).
    static func body(for status: FaceStatus, identity: FaceIdentity, shapeMode: Theme.BlobShapeMode, sleepy: Bool = false) -> BlobBody {
        switch shapeMode {
        case .status:
            return BlobBody.forStatus(status, sleepy: sleepy)
        case .identity:
            return BlobBody(shape: identity.shape, squash: sleepy ? Theme.blobSleepySquash : 1)
        }
    }

    /// The grow loop of a waiting face: every 3 s for a question, every 2 s for a permission prompt.
    static func attentionGrow(for kind: WaitingKind) -> AttentionGrow {
        kind == .permission ? Theme.permissionGrow : Theme.attentionGrow
    }

    /// Expression pose with the identity's subtle tilt and spacing deltas.
    static func resolved(_ expression: Expression, _ identity: FaceIdentity) -> BlobEyePose {
        BlobExpressions.pose(for: expression).varied(tilt: identity.blobTiltDelta, split: identity.blobSplitDelta)
    }

    // MARK: Status programs

    private static func program(for status: FaceStatus, identity: FaceIdentity, bodyOverride: BlobBody?, shapeMode: Theme.BlobShapeMode, activity: SessionActivity, colorMode: Theme.ColorMode, projectKey: String?, now: Date) -> BlobProgram {
        let color = color(for: status, identity: identity, colorMode: colorMode, projectKey: projectKey)
        func body(sleepy: Bool = false) -> BlobBody {
            bodyOverride ?? Self.body(for: status, identity: identity, shapeMode: shapeMode, sleepy: sleepy)
        }

        switch status {
        case .needsInput(let kind):
            let wide = resolved(identity.pick(.surprised, .awe, slot: 40), identity)
                .looking(yaw: Theme.blobNeedsInputYaw, pitch: Theme.blobNeedsInputPitch)
            let interval = identity.blinkInterval(in: Theme.needsInputBlinkInterval)
            let schedule = BlobBlinkSchedule(interval: interval, count: Theme.needsInputDoubleBlinkEvery, phase: identity.blinkPhase, doubleEvery: Theme.needsInputDoubleBlinkEvery)
            var program = BlobProgram(pose: wide, body: body(), color: color)
            program.tracks = [
                .sampled(key: "loop.blink", duration: interval * Double(Theme.needsInputDoubleBlinkEvery), repeats: true, events: schedule.events) { t in
                    wide.withLid(schedule.lid(at: t))
                },
            ]
            // A permission prompt is the more urgent wait: faster pulse, a grow every 2 s.
            program.bodyLoop = kind == .permission ? Theme.permissionPulse : Theme.blobNeedsInputPulse
            program.grow = attentionGrow(for: kind)
            program.halo = .attention(grow: program.grow!)
            program.restScale = Theme.attentionScale
            return program

        case .working:
            // The working face is the one that perks up when the person's message arrives (the
            // excited token, `ExcitedTracker`); an action face launching never does.
            var program = workingProgram(activity: activity, identity: identity, body: body(), color: color)
            program.excited = true
            return program

        case .yourTurn:
            // Catches the eye without the urgency of amber: the body swaps between two silhouettes and
            // hops a little with each swap (only the hop in `.identity` shape mode or with a forced
            // body), normal eyes look at the person with the idle blink rhythm, no wander, no grow.
            // The body, the halo and the edge cue are the your-turn lime in every colour mode.
            let attentive = resolved(.normal, identity).looking(yaw: Theme.blobNeedsInputYaw, pitch: Theme.blobNeedsInputPitch)
            var program = BlobProgram(pose: attentive, body: body(), color: color)
            program.tracks = [yourTurnTrack(attentive: attentive, identity: identity)]
            program.halo = .yourTurn(color: color)
            let swaps = shapeMode == .status && bodyOverride == nil
            program.swap = BlobShapeSwap(alternate: swaps ? BlobBody(shape: Theme.yourTurnShapes.1) : nil)
            return program

        case .idle(let since):
            let normal = resolved(.normal, identity)
            let sleepy = resolved(.sleepy, identity)
            let remaining = Theme.sleepyAfter - now.timeIntervalSince(since)
            let sleepyLoop = sleepyTrack(sleepy: sleepy, identity: identity, delay: max(remaining, 0) + Theme.blobSleepyDriftDuration)
            if remaining <= 0 {
                var program = BlobProgram(pose: sleepy, body: body(sleepy: true), color: color)
                program.tracks = [sleepyTrack(sleepy: sleepy, identity: identity, delay: 0)]
                return program
            }
            var program = BlobProgram(pose: normal, body: body(), color: color)
            program.tracks = [
                idleTrack(normal: normal, identity: identity, delay: 0),
                .move(key: "sched.sleepy", from: normal, to: sleepy, after: remaining, duration: Theme.blobSleepyDriftDuration),
                sleepyLoop,
            ]
            program.scheduledBody = BlobScheduledBody(body: body(sleepy: true), after: remaining, duration: Theme.blobSleepyDriftDuration)
            return program

        case .justFinished:
            let squint = resolved(.glee, identity)
            let normal = resolved(.normal, identity)
            var program = BlobProgram(pose: squint, body: body(), color: color)
            if colorMode == .status || (colorMode == .project && projectKey != nil) {
                program.flashColor = Theme.justFinishedColor
            }
            let swap = BlobTrack.blinkSwap(key: "sched.return", from: squint, to: normal, after: Theme.justFinishedHold)
            program.tracks = [
                swap,
                idleTrack(normal: normal, identity: identity, delay: Theme.justFinishedHold + swap.duration),
            ]
            program.bounce = true
            program.burst = true
            if program.flashColor != nil {
                program.halo = .done
            }
            return program

        case .ended:
            return BlobProgram(pose: resolved(.normal, identity).closed(), body: body(), color: color)
        }
    }

    // MARK: Action faces

    /// An action face: its own silhouette and colour (never a status). Resting: sleepy eyes with slow
    /// blinks. Hovered: eyes open to normal with the idle wander. Launching: the working cloud with the
    /// thinking drift and breath, in the action colour, so the click reads as "a session is starting".
    static func actionProgram(_ face: ActionFace, identity: FaceIdentity, bodyOverride: BlobBody?) -> BlobProgram {
        switch face.phase {
        case .resting:
            let resting = restingActionPose(identity)
            var program = BlobProgram(pose: resting, body: bodyOverride ?? BlobBody(shape: face.shape), color: face.color)
            program.tracks = [sleepyTrack(sleepy: resting, identity: identity, delay: 0)]
            return program
        case .hovered:
            let normal = resolved(.normal, identity)
            var program = BlobProgram(pose: normal, body: bodyOverride ?? BlobBody(shape: face.shape), color: face.color)
            program.tracks = [idleTrack(normal: normal, identity: identity, delay: 0)]
            return program
        case .launching:
            return workingProgram(activity: .thinking, identity: identity, body: bodyOverride ?? BlobBody(shape: Theme.blobWorkingShape), color: face.color)
        }
    }

    /// The calm resting eyes of an action face (`Theme.actionRestingEye`), with the identity's deltas.
    static func restingActionPose(_ identity: FaceIdentity) -> BlobEyePose {
        BlobEyePose(both: Theme.actionRestingEye, split: Theme.actionRestingSplit, lift: Theme.actionRestingLift)
            .varied(tilt: identity.blobTiltDelta, split: identity.blobSplitDelta)
    }

    /// The one-shot squint of a clicked action face: glee for `Theme.actionSquintDuration`, eased in
    /// and out, from and back to `pose`.
    static func squintTrack(from pose: BlobEyePose, identity: FaceIdentity) -> BlobTrack {
        let glee = resolved(.glee, identity).looking(yaw: pose.yaw, pitch: pose.pitch)
        let total = Theme.actionSquintDuration
        let edge = min(0.12, total / 3)
        return .sampled(key: "oneshot.squint", duration: total, repeats: false, events: [edge, total - edge]) { t in
            if t <= 0 || t >= total { return pose }
            if t < edge { return BlobEyePose.lerp(pose, glee, t: BlobMotion.easeOut(t / edge)) }
            if t > total - edge { return BlobEyePose.lerp(glee, pose, t: BlobMotion.easeOut(min((t - (total - edge)) / edge, 1))) }
            return glee
        }
    }

    // MARK: Excited

    /// The excited eyes: `pose` opened wide (`Theme.excitedEyeScale` taller, `Theme.excitedEyeWiden`
    /// wider), lids open, looking at the person (the needs-input gaze).
    static func excitedPose(from pose: BlobEyePose) -> BlobEyePose {
        var wide = pose.looking(yaw: Theme.blobNeedsInputYaw, pitch: Theme.blobNeedsInputPitch).withLid(1)
        for keyPath in [\BlobEyePose.left, \BlobEyePose.right] {
            wide[keyPath: keyPath].height *= Theme.excitedEyeScale
            wide[keyPath: keyPath].width *= Theme.excitedEyeWiden
        }
        return wide
    }

    /// The eyes of the excited reaction: from `pose` to the excited pose within `Theme.excitedEyeOpen`
    /// (ease-out), held, and back to `pose` over the last `Theme.excitedEyeRelease` (ease-out), in
    /// `Theme.excitedDuration`, starting `delay` from now. One-shot; it ends where the working loops begin.
    static func excitedTrack(from pose: BlobEyePose, delay: TimeInterval) -> BlobTrack {
        let wide = excitedPose(from: pose)
        let total = Theme.excitedDuration
        let open = Theme.excitedEyeOpen
        let release = total - Theme.excitedEyeRelease
        return .sampled(key: "oneshot.excited", duration: total, repeats: false, delay: delay, events: [open, release]) { t in
            if t <= 0 || t >= total { return pose }
            if t < open { return BlobEyePose.lerp(pose, wide, t: BlobMotion.easeOut(t / open)) }
            if t > release { return BlobEyePose.lerp(wide, pose, t: BlobMotion.easeOut(min((t - release) / Theme.excitedEyeRelease, 1))) }
            return wide
        }
    }

    // MARK: Working substates

    /// The working face per activity: every substate is one repeating eye track (plus the body
    /// breath), keyed by activity so a change replaces it inside a blink. All moves are ease-outs.
    static func workingProgram(activity: SessionActivity, identity: FaceIdentity, body: BlobBody, color: EyeColor) -> BlobProgram {
        let focused = resolved(.focused, identity)
        let tempo = identity.hash.value(in: Theme.blobActivityTempo, slot: 60)
        var program: BlobProgram
        switch activity {
        case .thinking:
            // The drift script runs a little faster or slower per seed, so working faces never move in step.
            let driftTempo = 0.85 + 0.3 * identity.dartPhase
            program = BlobProgram(pose: focused, body: body, color: color)
            program.tracks = [thinkingTrack(focused: focused, tempo: driftTempo)]
        case .coding:
            var narrowed = focused
            narrowed.left.height *= Theme.blobCodingEyeHeightScale
            narrowed.right.height *= Theme.blobCodingEyeHeightScale
            let rest = narrowed.glancing(yaw: Theme.blobCodingYawRange.lowerBound, pitch: Theme.blobCodingPitch)
            program = BlobProgram(pose: rest, body: body, color: color)
            program.tracks = [codingTrack(narrowed: narrowed, tempo: tempo)]
        case .running:
            let rest = focused.glancing(yaw: Theme.blobRunningYaw, pitch: Theme.blobRunningPitch)
            program = BlobProgram(pose: rest, body: body, color: color)
            program.tracks = [runningTrack(focused: focused, tempo: tempo)]
            program.eyePulse = Theme.blobRunningEyePulse
        case .reading:
            let rest = focused.glancing(yaw: Theme.blobReadingYawRange.lowerBound, pitch: Theme.blobReadingLinePitch.upperBound)
            program = BlobProgram(pose: rest, body: body, color: color)
            program.tracks = [readingTrack(focused: focused, tempo: tempo)]
        case .delegating:
            var up = focused.glancing(yaw: 0, pitch: Theme.blobDelegatingPitch)
            up.split += Theme.blobDelegatingSplitDelta
            program = BlobProgram(pose: up, body: body, color: color)
            program.tracks = [delegatingTrack(up: up, identity: identity)]
        }
        program.bodyLoop = Theme.blobWorkingBreath
        return program
    }

    /// Thinking: gaze drift up-left, right, centre, one blink at the return.
    static func thinkingTrack(focused: BlobEyePose, tempo: Double) -> BlobTrack {
        let targets = Theme.blobWorkingGazeTargets.map { (time: $0.time * tempo, yaw: $0.yaw, pitch: $0.pitch) }
        let duration = Theme.blobWorkingLoopDuration * tempo
        let schedule = BlobBlinkSchedule(starts: [Theme.blobWorkingBlinkTime * tempo])
        let events = schedule.events + targets.flatMap { [$0.time, $0.time + Theme.blobGazeMoveDuration] }
        return .sampled(key: "loop.drift", duration: duration, repeats: true, events: events) { t in
            let gaze = BlobMotion.gaze(at: t, targets: targets)
            return focused.glancing(yaw: gaze.yaw, pitch: gaze.pitch).withLid(schedule.lid(at: t))
        }
    }

    /// Coding: the gaze follows a typed line in small steps left to right, snaps back with a blink, pauses.
    static func codingTrack(narrowed: BlobEyePose, tempo: Double) -> BlobTrack {
        let steps = Theme.blobCodingSteps
        let line = Theme.blobCodingLineDuration * tempo
        let stepMove = Theme.blobCodingStepMove * tempo
        let returnDuration = Theme.blobCodingReturnDuration * tempo
        let duration = Theme.blobCodingLoopDuration * tempo
        let range = Theme.blobCodingYawRange
        let stepTime = line / Double(steps)
        var targets: [(time: Double, yaw: Double, pitch: Double)] = (0..<steps).map { index in
            let fraction = steps > 1 ? Double(index) / Double(steps - 1) : 0
            return (Double(index) * stepTime, range.lowerBound + (range.upperBound - range.lowerBound) * fraction, Theme.blobCodingPitch)
        }
        let returnStart = line
        let schedule = BlobBlinkSchedule(starts: [returnStart])
        let events = schedule.events + targets.flatMap { [$0.time, $0.time + stepMove] } + [returnStart, returnStart + returnDuration]
        targets.append((returnStart, range.lowerBound, Theme.blobCodingPitch))
        return .sampled(key: "loop.code", duration: duration, repeats: true, events: events) { t in
            let gaze = BlobMotion.gaze(at: t, targets: targets, moveDuration: t < returnStart ? stepMove : returnDuration)
            return narrowed.glancing(yaw: gaze.yaw, pitch: gaze.pitch).withLid(schedule.lid(at: t))
        }
    }

    /// Running: the eyes sit down-left watching the output; once per loop they glance to centre,
    /// hold, and drop back down with a blink. The cursor pulse is a separate opacity loop.
    static func runningTrack(focused: BlobEyePose, tempo: Double) -> BlobTrack {
        let duration = Theme.blobRunningLoopDuration * tempo
        let glance = Theme.blobRunningGlanceTime * tempo
        let drop = glance + Theme.blobRunningGlanceHold
        let targets: [(time: Double, yaw: Double, pitch: Double)] = [
            (0, Theme.blobRunningYaw, Theme.blobRunningPitch), (glance, 0, 0), (drop, Theme.blobRunningYaw, Theme.blobRunningPitch),
        ]
        let move = Theme.blobCodingReturnDuration
        let schedule = BlobBlinkSchedule(starts: [drop])
        let events = schedule.events + targets.flatMap { [$0.time, $0.time + move] }
        return .sampled(key: "loop.run", duration: duration, repeats: true, events: events) { t in
            let gaze = BlobMotion.gaze(at: t, targets: targets, moveDuration: move)
            return focused.glancing(yaw: gaze.yaw, pitch: gaze.pitch).withLid(schedule.lid(at: t))
        }
    }

    /// Reading: a steady sweep left to right on the upper line, a quick drop to the lower line,
    /// a second sweep, a short hold, then back up to the start with a blink.
    static func readingTrack(focused: BlobEyePose, tempo: Double) -> BlobTrack {
        let sweep = Theme.blobReadingSweepDuration * tempo
        let dropLength = Theme.blobReadingLineDropDuration * tempo
        let hold = Theme.blobReadingEndHold * tempo
        let back = Theme.blobReadingReturnDuration * tempo
        let duration = Theme.blobReadingPeriod * tempo
        let yaws = Theme.blobReadingYawRange
        let pitches = Theme.blobReadingLinePitch
        let dropStart = sweep
        let secondStart = dropStart + dropLength
        let holdStart = secondStart + sweep
        let returnStart = holdStart + hold
        let schedule = BlobBlinkSchedule(starts: [returnStart])
        let events = schedule.events + [dropStart, secondStart, holdStart, returnStart, returnStart + back]
        func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
        func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
        return .sampled(key: "loop.read", duration: duration, repeats: true, events: events) { t in
            let yaw: Double
            let pitch: Double
            if t < dropStart {
                yaw = mix(yaws.lowerBound, yaws.upperBound, smooth(t / sweep))
                pitch = pitches.upperBound
            } else if t < secondStart {
                let p = BlobMotion.easeOut((t - dropStart) / dropLength)
                yaw = mix(yaws.upperBound, yaws.lowerBound, p)
                pitch = mix(pitches.upperBound, pitches.lowerBound, p)
            } else if t < holdStart {
                yaw = mix(yaws.lowerBound, yaws.upperBound, smooth((t - secondStart) / sweep))
                pitch = pitches.lowerBound
            } else if t < returnStart {
                yaw = yaws.upperBound
                pitch = pitches.lowerBound
            } else {
                let p = BlobMotion.easeOut((t - returnStart) / back)
                yaw = mix(yaws.upperBound, yaws.lowerBound, p)
                pitch = mix(pitches.lowerBound, pitches.upperBound, p)
            }
            return focused.glancing(yaw: yaw, pitch: pitch).withLid(schedule.lid(at: t))
        }
    }

    /// Delegating: eyes up and a little apart, still, with a slow blink every so often (seeded).
    static func delegatingTrack(up: BlobEyePose, identity: FaceIdentity) -> BlobTrack {
        let interval = identity.blinkInterval(in: Theme.blobDelegatingBlinkInterval)
        let schedule = BlobBlinkSchedule(interval: interval, count: 1, phase: identity.blinkPhase, durationScale: Theme.blobDelegatingBlinkScale)
        return .sampled(key: "loop.delegate", duration: interval, repeats: true, events: schedule.events) { t in
            up.withLid(schedule.lid(at: t))
        }
    }

    // MARK: Tracks

    /// The idle loop: the gaze wanders on a tiny figure of eight while the lids blink every
    /// interval (seeded), every n-th a double blink. Starts at the rest pose, so it chains
    /// seamlessly after a transition.
    static func idleTrack(normal: BlobEyePose, identity: FaceIdentity, delay: TimeInterval) -> BlobTrack {
        let interval = identity.blinkInterval(in: Theme.idleBlinkInterval)
        let count = Theme.blobIdleLoopBlinks
        let duration = interval * Double(count)
        let period = duration / max((duration / Theme.blobWanderPeriod).rounded(), 1)
        let schedule = BlobBlinkSchedule(interval: interval, count: count, phase: identity.blinkPhase, doubleEvery: Theme.idleDoubleBlinkEvery)
        return .sampled(key: "loop.idle", duration: duration, repeats: true, delay: delay, events: schedule.events) { t in
            let yaw = Theme.blobWanderYaw * sin(2 * .pi * t / period)
            let pitch = Theme.blobWanderPitch * sin(4 * .pi * t / period)
            return normal.glancing(yaw: yaw, pitch: pitch).withLid(schedule.lid(at: t))
        }
    }

    /// Your turn: the idle blink schedule (seeded interval, every n-th a double blink) on a still
    /// pose that looks at the person.
    static func yourTurnTrack(attentive: BlobEyePose, identity: FaceIdentity) -> BlobTrack {
        let interval = identity.blinkInterval(in: Theme.idleBlinkInterval)
        let count = Theme.blobIdleLoopBlinks
        let schedule = BlobBlinkSchedule(interval: interval, count: count, phase: identity.blinkPhase, doubleEvery: Theme.idleDoubleBlinkEvery)
        return .sampled(key: "loop.yourTurn", duration: interval * Double(count), repeats: true, events: schedule.events) { t in
            attentive.withLid(schedule.lid(at: t))
        }
    }

    /// Sleepy: slow blinks, no wander.
    static func sleepyTrack(sleepy: BlobEyePose, identity: FaceIdentity, delay: TimeInterval) -> BlobTrack {
        let interval = identity.blinkInterval(in: Theme.sleepyBlinkInterval)
        let schedule = BlobBlinkSchedule(interval: interval, count: 1, phase: identity.blinkPhase)
        return .sampled(key: "loop.sleepy", duration: interval, repeats: true, delay: delay, events: schedule.events) { t in
            sleepy.withLid(min(schedule.lid(at: t), sleepy.lid))
        }
    }
}
