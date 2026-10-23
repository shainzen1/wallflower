import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import AgentOverview

/// The excited reaction: a resting or waiting session that starts working (the person's message
/// arrived) makes its face perk up once, in Core Animation one-shots, and then work as usual.
@Suite("Excited: the face perks up when the person's message arrives")
@MainActor
struct ExcitedTests {
    private let identity = FaceIdentity(seed: "excited")
    private let fresh = Date()
    /// An idle period older than `Theme.sleepyAfter`: the sleepy face.
    private var sleepy: FaceStatus { .idle(since: Date().addingTimeInterval(-Theme.sleepyAfter - 60)) }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Trigger rule

    @Test("Only idle, sleepy, your turn, just finished and waiting to working excite; working to working does not")
    func rule() {
        let resting: [FaceStatus] = [
            .idle(since: fresh), sleepy, .yourTurn(since: fresh), .justFinished,
            .needsInput(kind: .question), .needsInput(kind: .permission), .needsInput(kind: .other),
        ]
        for old in resting {
            #expect(ExcitedTracker.excites(from: old, to: .working), "\(old) to working")
        }
        #expect(!ExcitedTracker.excites(from: .working, to: .working), "a new activity is no new message")
        #expect(!ExcitedTracker.excites(from: .ended, to: .working))
        let others: [FaceStatus] = [.idle(since: fresh), .yourTurn(since: fresh), .justFinished, .needsInput(kind: .question), .ended]
        for new in others {
            for old in resting + [.working] {
                #expect(!ExcitedTracker.excites(from: old, to: new), "\(old) to \(new)")
            }
        }
    }

    @Test("The tracker bumps once per message, never on a session's first appearance, and forgets departed sessions")
    func tracker() {
        var tracker = ExcitedTracker()
        let step1 = tracker.observe(key: 1, status: .working)
        #expect(!step1, "a new session that arrives working: no reaction")
        let step2 = tracker.observe(key: 2, status: .idle(since: fresh))
        #expect(!step2, "a new idle session: nothing yet")
        #expect(tracker.token(for: 1) == 0 && tracker.token(for: 2) == 0)
        let step3 = tracker.observe(key: 2, status: .working)
        #expect(step3, "its first message")
        #expect(tracker.token(for: 2) == 1)
        let step4 = tracker.observe(key: 2, status: .working)
        #expect(!step4, "still working")
        let step5 = tracker.observe(key: 2, status: .justFinished)
        #expect(!step5)
        let step6 = tracker.observe(key: 2, status: .working)
        #expect(step6, "a reply within the done moment")
        let step7 = tracker.observe(key: 2, status: .needsInput(kind: .permission))
        #expect(!step7)
        let step8 = tracker.observe(key: 2, status: .working)
        #expect(step8, "the permission was granted")
        #expect(tracker.token(for: 2) == 3 && tracker.token(for: 1) == 0)
        tracker.keep(keys: [1])
        #expect(tracker.token(for: 2) == 0)
        let step9 = tracker.observe(key: 2, status: .working)
        #expect(!step9, "a forgotten session counts as new again")
        let step10 = tracker.observe(key: 1, status: sleepy)
        #expect(!step10)
        let step11 = tracker.observe(key: 1, status: .working)
        #expect(step11, "sleepy to working")
    }

    @Test("The panel model bumps a row's excited token on the rule, next to the attention hop")
    func model() {
        let model = PanelModel(store: SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil))
        model.noteStatus(key: 7, status: .working)
        #expect(model.excitedToken(for: 7) == 0, "first seen working")
        model.noteStatus(key: 7, status: .needsInput(kind: .question))
        #expect(model.attentionToken(for: 7) == 1 && model.excitedToken(for: 7) == 0)
        model.noteStatus(key: 7, status: .working)
        #expect(model.excitedToken(for: 7) == 1 && model.attentionToken(for: 7) == 1)
        model.noteStatus(key: 7, status: .working)
        #expect(model.excitedToken(for: 7) == 1)
        model.noteStatus(key: 8, status: .yourTurn(since: fresh))
        model.noteStatus(key: 8, status: .working)
        #expect(model.excitedToken(for: 8) == 1 && model.excitedToken(for: 7) == 1)
        #expect(model.exciteWorkingRows() == 0, "no rows in an empty store")
    }

    // MARK: Program flag

    @Test("Only the working program has the excited reaction, in every substate and colour mode")
    func programFlag() {
        for activity in SessionActivity.allCases {
            for colorMode in Theme.ColorMode.allCases {
                let program = BlobProgramBuilder.program(for: .status(.working), identity: identity, activity: activity, colorMode: colorMode, projectKey: "repo")
                #expect(program.excited, "\(activity), \(colorMode)")
            }
        }
        let others: [FaceStatus] = [.needsInput(kind: .question), .yourTurn(since: fresh), .idle(since: fresh), .justFinished, .ended]
        for status in others {
            #expect(!BlobProgramBuilder.program(for: .status(status), identity: identity).excited, "\(status)")
        }
        #expect(!BlobProgramBuilder.program(for: .action(ActionFace(phase: .launching)), identity: identity).excited, "an action launching never")
        #expect(!BlobProgramBuilder.program(for: .expression(.surprised), identity: identity).excited)
    }

    @Test("The constants: a 0.5 to 0.7 s burst whose parts all end within it; wide eyes, a brighter body")
    func constants() {
        #expect(Theme.excitedDuration >= 0.5 && Theme.excitedDuration <= 0.7)
        #expect(BlobAnimations.excitedLanding + Theme.excitedSquashDuration <= Theme.excitedDuration, "hops and squash end inside the burst")
        #expect(Theme.excitedEyeOpen + Theme.excitedEyeRelease < Theme.excitedDuration && Theme.excitedBrightPeak < Theme.excitedDuration)
        let pose = BlobProgramBuilder.resolved(.focused, identity)
        let wide = BlobProgramBuilder.excitedPose(from: pose)
        #expect(wide.left.height > pose.left.height * 1.2 && wide.right.width > pose.right.width && wide.lid == 1)
        let track = BlobProgramBuilder.excitedTrack(from: pose, delay: 0.2)
        #expect(track.key.hasPrefix("oneshot.") && !track.repeats && track.delay == 0.2 && abs(track.duration - Theme.excitedDuration) < 0.000_1)
        #expect(track.samples.first?.pose == pose && track.samples.last?.pose == pose, "starts and ends on the working pose")
        let cyan = Theme.workingColor
        let bright = cyan.brightened(Theme.excitedBrighten)
        #expect(bright.red > cyan.red && bright.green >= cyan.green && bright.blue >= cyan.blue && bright.red <= 1)
        #expect(cyan.brightened(0) == EyeColor(name: "\(cyan.name) bright", red: cyan.red, green: cyan.green, blue: cyan.blue))
    }

    // MARK: Layer tree

    private struct Layers {
        let haloHost: CALayer
        let face: CALayer
        let scaler: CALayer
        let body: CAShapeLayer
        let eyes: [CAShapeLayer]
    }

    private func layers(of root: CALayer) throws -> Layers {
        let haloHost = try #require(root.sublayers?[0].sublayers?.first?.sublayers?.first)
        let face = try #require(root.sublayers?[2].sublayers?.last)
        let scaler = try #require(face.sublayers?.first?.sublayers?.first)
        let body = try #require(scaler.sublayers?.first as? CAShapeLayer)
        let eyes = (scaler.sublayers?.last?.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        return Layers(haloHost: haloHost, face: face, scaler: scaler, body: body, eyes: eyes)
    }

    private func tree(_ status: FaceStatus) -> (BlobLayerTree, CALayer, FaceConfiguration) {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: Theme.faceSize, height: Theme.faceSize)
        let tree = BlobLayerTree(root: root)
        let config = FaceConfiguration(identity: identity, mode: .status(status), size: Theme.faceSize, filter: .none, blobShapeMode: .status, colorMode: .status)
        tree.apply(config)
        return (tree, root, config)
    }

    @Test("A token bump on a working face plays one-shots only: wide eyes, two hops with the glow, a wiggle, a brighter body")
    func playsOneShots() throws {
        guard !reduceMotion else { return }
        var (tree, root, config) = tree(.yourTurn(since: fresh))
        let l = try layers(of: root)
        config.mode = .status(.working)
        tree.apply(config)
        let loopsBefore = l.eyes.compactMap { $0.animation(forKey: "loop.drift")?.beginTime }
        config.excitedToken += 1
        tree.apply(config)
        let now = l.face.convertTime(CACurrentMediaTime(), from: nil)

        let hops = try #require(l.face.animation(forKey: "oneshot.excited") as? CAAnimationGroup)
        let glow = try #require(l.haloHost.animation(forKey: "oneshot.excitedLift") as? CAAnimationGroup)
        let wiggle = try #require(l.scaler.animation(forKey: "oneshot.excitedWiggle") as? CAAnimationGroup)
        for group in [hops, glow, wiggle] {
            #expect(group.repeatCount == 0 && group.isRemovedOnCompletion, "a one-shot, gone when over")
            #expect(group.beginTime + group.duration <= now + Theme.excitedDuration + 0.05)
        }
        // The blink of the state change is still closing the lids: everything waits for it to open.
        let wait = hops.beginTime - now
        #expect(wait > 0.05 && wait <= BlobTrack.blinkSwap(key: "x", from: .init(), to: .init()).duration + 0.01, "starts as the lids open (\(wait))")
        #expect(abs(glow.beginTime - hops.beginTime) < 0.01 && glow.duration == hops.duration, "the glow lifts with the face")
        let lifts = (hops.animations ?? []).compactMap { $0 as? CAKeyframeAnimation }
        #expect(lifts.count == 2 && lifts.allSatisfy { $0.keyPath == "transform.translation.y" && $0.isAdditive }, "a double hop")
        let heights = lifts.map { ($0.values as? [Double])?.max() ?? 0 }
        #expect(abs(heights[0] - Theme.excitedHopHeight * Theme.faceSize) < 0.000_1 && heights[1] < heights[0])
        let parts = (wiggle.animations ?? []).compactMap { $0 as? CAKeyframeAnimation }
        #expect(parts.contains { $0.keyPath == "transform.rotation.z" && $0.isAdditive }, "the wiggle on the body")
        #expect(parts.contains { $0.keyPath == "transform.scale.y" && $0.isAdditive }, "the squash on the body")

        for eye in l.eyes {
            let track = try #require(eye.animation(forKey: "oneshot.excited") as? CAKeyframeAnimation)
            #expect(abs(track.duration - Theme.excitedDuration) < 0.001 && track.isRemovedOnCompletion)
            #expect(abs(track.beginTime - hops.beginTime) < 0.01, "the eyes widen with the first hop")
        }
        // The working loops wait for the reaction and start where it ends.
        let loopsAfter = l.eyes.compactMap { $0.animation(forKey: "loop.drift")?.beginTime }
        #expect(loopsAfter.count == 2 && loopsBefore.count == 2)
        for begin in loopsAfter {
            #expect(abs(begin - (hops.beginTime + Theme.excitedDuration)) < 0.01, "the drift begins after the reaction")
        }

        let color = try #require(l.body.animation(forKey: "color.fill") as? CAKeyframeAnimation)
        let values = try #require(color.values as? [CGColor])
        let cyan = Theme.workingColor.cgColor
        #expect(values.count == 4 && values[1] == cyan && values.last == cyan && values[2] == Theme.workingColor.brightened(Theme.excitedBrighten).cgColor)
        #expect(l.body.fillColor == cyan, "the model colour stays the working colour")
    }

    @Test("A face without the reaction ignores the token; a token bump without a state change starts at once")
    func gating() throws {
        guard !reduceMotion else { return }
        var (tree, root, config) = tree(.idle(since: fresh))
        let l = try layers(of: root)
        config.excitedToken += 1
        tree.apply(config)
        #expect(l.face.animation(forKey: "oneshot.excited") == nil && l.haloHost.animation(forKey: "oneshot.excitedLift") == nil)
        #expect(l.eyes.allSatisfy { $0.animation(forKey: "oneshot.excited") == nil })

        // The playground's button on a face that is already working: no blink to wait for.
        var (working, workingRoot, workingConfig) = self.tree(.working)
        let w = try layers(of: workingRoot)
        workingConfig.excitedToken += 1
        // Bracketed by clock reads around the call, not "within 20 ms of a later read": a busy main
        // thread can be preempted after the call for longer than any fixed tolerance.
        let before = w.face.convertTime(CACurrentMediaTime(), from: nil)
        working.apply(workingConfig)
        let after = w.face.convertTime(CACurrentMediaTime(), from: nil)
        let hops = try #require(w.face.animation(forKey: "oneshot.excited"))
        #expect(before <= hops.beginTime && hops.beginTime <= after, "right away (\(hops.beginTime - before) s after the call began, which took \(after - before) s)")
    }
}
