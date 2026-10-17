import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import AgentOverview

/// The your-turn loop: the body swaps between two silhouettes and hops with every swap, in Core
/// Animation, seeded per face, paused under the pointer, and handed over cleanly on a state change.
@Suite("Your turn motion: shape swap, hop, hover pause, reach")
@MainActor
struct YourTurnMotionTests {
    private let turn = FaceStatus.yourTurn(since: Date())

    private func program(shapeMode: Theme.BlobShapeMode = .status, bodyOverride: BlobBody? = nil, seed: String = "m") -> BlobProgram {
        BlobProgramBuilder.program(for: .status(turn), identity: FaceIdentity(seed: seed), bodyOverride: bodyOverride, shapeMode: shapeMode, colorMode: .status)
    }

    /// The layers the motion lives on: the scaler, the body and the eye group's mask.
    private struct Layers {
        let scaler: CALayer
        let body: CAShapeLayer
        let bodyMask: CAShapeLayer
        let eyes: [CAShapeLayer]
    }

    private func layers(of root: CALayer) throws -> Layers {
        let magnify = try #require(root.sublayers?[2])
        let face = try #require(magnify.sublayers?.last)
        let genie = try #require(face.sublayers?.first)
        let scaler = try #require(genie.sublayers?.first)
        let body = try #require(scaler.sublayers?.first as? CAShapeLayer)
        let eyeGroup = try #require(scaler.sublayers?.last)
        let bodyMask = try #require(eyeGroup.mask as? CAShapeLayer)
        let eyes = (eyeGroup.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        return Layers(scaler: scaler, body: body, bodyMask: bodyMask, eyes: eyes)
    }

    private func tree(_ config: FaceConfiguration) -> (BlobLayerTree, CALayer) {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: config.size, height: config.size)
        let tree = BlobLayerTree(root: root)
        tree.apply(config)
        return (tree, root)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Program

    @Test("The constants: two silhouettes that are neither the drop nor the same, 1.4 s holds, 0.35 s morphs, a 3 pt hop")
    func constants() {
        #expect(Theme.yourTurnShapes.0 == Theme.blobIdleShape, "rests on the idle pill, so the done moment glides in")
        #expect(Theme.yourTurnShapes.0 != Theme.yourTurnShapes.1)
        #expect(Theme.yourTurnShapes.1 != Theme.blobNeedsInputShape && Theme.yourTurnShapes.0 != Theme.blobNeedsInputShape, "never the needs-input drop")
        #expect(Theme.yourTurnSwapHold == 1.4 && Theme.yourTurnSwapDuration == 0.35)
        #expect(abs(Theme.yourTurnBounceHeight * Theme.faceSize - 3) < 0.000_1)
        #expect(Theme.yourTurnBounceDuration <= Theme.yourTurnSwapHold, "the face has landed long before the next swap")
        let swap = BlobShapeSwap(alternate: nil)
        #expect(swap.period == 3.5 && swap.swapTimes == [0, 1.75])
    }

    @Test("Status shape mode swaps silhouettes; identity shape mode and a forced body only hop; no other status has it")
    func programs() {
        let status = program()
        #expect(status.body == BlobBody(shape: Theme.yourTurnShapes.0))
        #expect(status.swap == BlobShapeSwap(alternate: BlobBody(shape: Theme.yourTurnShapes.1)))
        let identity = program(shapeMode: .identity, seed: "seeded")
        #expect(identity.body == BlobBody(shape: FaceIdentity(seed: "seeded").shape))
        #expect(identity.swap == BlobShapeSwap(alternate: nil), "the seed's silhouette stays, only the hop plays")
        #expect(program(bodyOverride: BlobBody(shape: .bean)).swap?.alternate == nil)
        #expect(status.tracks.map(\.key) == ["loop.yourTurn"], "the eyes keep the attentive pose and the idle blink rhythm")
        for other: FaceStatus in [.needsInput(kind: .question), .working, .idle(since: Date()), .justFinished, .ended] {
            let other = BlobProgramBuilder.program(for: .status(other), identity: FaceIdentity(seed: "m"), shapeMode: .status, colorMode: .status)
            #expect(other.swap == nil)
        }
    }

    // MARK: Animations

    @Test("The swap starts and ends on the resting path, morphs ease in and out, repeats forever")
    func swapAnimation() {
        let swap = BlobShapeSwap(alternate: BlobBody(shape: .round))
        let first = BlobShape.pill.profile.path(size: Theme.faceSize)
        let second = BlobShape.round.profile.path(size: Theme.faceSize)
        let animation = BlobAnimations.shapeSwap(first: first, second: second, swap: swap, begin: 12)
        let values = (animation.values ?? []).map { $0 as! CGPath }
        #expect(values.count == 5 && values.first == first && values.last == first && values[1] == second && values[2] == second)
        let times = (animation.keyTimes ?? []).map(\.doubleValue)
        #expect(times.count == 5 && times.first == 0 && times.last == 1)
        #expect(abs(times[1] * swap.period - 0.35) < 0.000_1 && abs(times[2] * swap.period - 1.75) < 0.000_1 && abs(times[3] * swap.period - 2.1) < 0.000_1)
        #expect(animation.duration == swap.period && animation.repeatCount == .infinity && animation.beginTime == 12)
        #expect(animation.timingFunctions?[0] == CAMediaTimingFunction(name: .easeInEaseOut))
        // Every keyframe path has the same element count, so Core Animation morphs instead of snapping.
        #expect(Set(values.map(Self.elementCount)).count == 1)
    }

    @Test("A hop of 3 pt with every swap, additive, with a squash on landing, in step with the swap")
    func bounceAnimation() throws {
        let swap = BlobShapeSwap(alternate: nil)
        let group = BlobAnimations.swapBounce(swap, size: Theme.faceSize, begin: 7)
        #expect(group.duration == swap.period && group.repeatCount == .infinity && group.beginTime == 7)
        let animations = try #require(group.animations as? [CAKeyframeAnimation])
        let lifts = animations.filter { $0.keyPath == "transform.translation.y" }
        #expect(lifts.map(\.beginTime) == swap.swapTimes)
        for lift in lifts {
            let peak = try #require((lift.values as? [Double])?.max())
            #expect(abs(peak - 3) < 0.000_1 && lift.isAdditive)
            #expect(lift.timingFunctions == [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)], "ease-out up, ease-in down")
        }
        let squashes = animations.filter { $0.keyPath == "transform.scale.y" }
        #expect(squashes.map(\.beginTime) == swap.swapTimes.map { $0 + Theme.yourTurnBounceDuration }, "on landing")
        #expect(squashes.allSatisfy { $0.isAdditive && (($0.values as? [Double])?.min() ?? 0) < 0 })
    }

    // MARK: Layer tree

    @Test("The tree runs the swap on the body and its mask and the hop on the scaler, seeded per face")
    func treeInstallsSwap() throws {
        guard !reduceMotion else { return }
        var starts: [CFTimeInterval] = []
        for seed in ["face-a", "face-b"] {
            let config = FaceConfiguration(identity: FaceIdentity(seed: seed), mode: .status(turn), size: Theme.faceSize, filter: .none, blobShapeMode: .status, colorMode: .status)
            let (_, root) = tree(config)
            let l = try layers(of: root)
            let swap = try #require(l.body.animation(forKey: "loop.swap") as? CAKeyframeAnimation)
            let maskSwap = try #require(l.bodyMask.animation(forKey: "loop.swap") as? CAKeyframeAnimation)
            let bounce = try #require(l.scaler.animation(forKey: "loop.bounce"))
            #expect(swap.repeatCount == .infinity && maskSwap.values?.count == swap.values?.count)
            #expect(abs(swap.beginTime - bounce.beginTime) < 0.01, "the hop goes with the swap")
            #expect((swap.values?.first as! CGPath) == l.body.path, "it starts on the resting body: no jump while it waits")
            #expect(l.eyes.allSatisfy { $0.animation(forKey: "loop.yourTurn") != nil })
            starts.append(swap.beginTime - l.body.convertTime(CACurrentMediaTime(), from: nil))
        }
        #expect(abs(starts[0] - starts[1]) > 0.05, "two faces never swap in step: \(starts)")
    }

    @Test("Identity shape mode keeps the seed's silhouette and only hops")
    func identityOnlyHops() throws {
        guard !reduceMotion else { return }
        let config = FaceConfiguration(identity: FaceIdentity(seed: "id"), mode: .status(turn), size: Theme.faceSize, filter: .none, blobShapeMode: .identity, colorMode: .status)
        let (_, root) = tree(config)
        let l = try layers(of: root)
        #expect(l.body.animation(forKey: "loop.swap") == nil)
        #expect(l.scaler.animation(forKey: "loop.bounce") != nil)
    }

    @Test("A hovered face rests: swap and hop pause under every hover effect, and come back after it", arguments: Theme.HoverEffect.allCases)
    func hoverPauses(effect: Theme.HoverEffect) throws {
        guard !reduceMotion else { return }
        var config = FaceConfiguration(identity: FaceIdentity(seed: "hover"), mode: .status(turn), size: Theme.faceSize, filter: .none, blobShapeMode: .status, colorMode: .status)
        config.hoverEffect = effect
        let (tree, root) = tree(config)
        let l = try layers(of: root)
        #expect(BlobLayerTree.pausesSwap(config, program: program()) == false)
        config.hovered = true
        #expect(BlobLayerTree.pausesSwap(config, program: program()))
        tree.apply(config)
        #expect(l.body.animation(forKey: "loop.swap") == nil && l.bodyMask.animation(forKey: "loop.swap") == nil)
        #expect(l.scaler.animation(forKey: "loop.bounce") == nil)
        config.hovered = false
        tree.apply(config)
        let swap = try #require(l.body.animation(forKey: "loop.swap") as? CAKeyframeAnimation)
        #expect(l.scaler.animation(forKey: "loop.bounce") != nil)
        let pill = BlobShape.pill.profile.path(size: Theme.faceSize)
        #expect((swap.values?.first as! CGPath) == pill, "never the stretched path")
        let idleProgram = BlobProgramBuilder.program(for: .status(.idle(since: Date())), identity: FaceIdentity(seed: "hover"))
        config.hovered = true
        #expect(!BlobLayerTree.pausesSwap(config, program: idleProgram), "nothing to pause on an idle face")
    }

    @Test("The done moment still glides into your turn; leaving your turn ends the loop with a morph from the screen")
    func handOver() throws {
        guard !reduceMotion else { return }
        var config = FaceConfiguration(identity: FaceIdentity(seed: "hand"), mode: .status(.justFinished), size: Theme.faceSize, filter: .none, blobShapeMode: .status, colorMode: .status)
        let (tree, root) = tree(config)
        let l = try layers(of: root)
        #expect(l.body.animation(forKey: "loop.swap") == nil)
        let done = config
        config.mode = .status(turn)
        #expect(BlobLayerTree.glides(from: done, to: config))
        tree.apply(config)
        #expect(l.eyes.allSatisfy { $0.animation(forKey: "oneshot.glide") != nil }, "the glide, no blink")
        #expect(l.eyes.allSatisfy { $0.animation(forKey: "oneshot.transition") == nil })
        let swap = try #require(l.body.animation(forKey: "loop.swap"))
        let now = l.body.convertTime(CACurrentMediaTime(), from: nil)
        #expect(swap.beginTime - now >= Theme.yourTurnGlideDuration - 0.01, "the swap waits for the glide")
        #expect(l.body.animation(forKey: "morph") == nil, "the same pill: nothing morphs on the way in")

        config.mode = .status(.idle(since: Date()))
        tree.apply(config)
        #expect(l.body.animation(forKey: "loop.swap") == nil && l.scaler.animation(forKey: "loop.bounce") == nil)
        #expect(l.body.animation(forKey: "morph") != nil && l.bodyMask.animation(forKey: "morph") != nil, "the body morphs on from whatever silhouette was showing")
        #expect(l.body.path == BlobShape.pill.profile.path(size: Theme.faceSize))
    }

    // MARK: Reach

    @Test("The reach covers the larger silhouette and the hop; hovered it is the resting pill")
    func reach() {
        let pill = FaceReach.extent(of: Theme.yourTurnShapes.0)
        let round = FaceReach.extent(of: Theme.yourTurnShapes.1)
        let size = Theme.faceSize
        let resting = FaceReach.session(status: turn, seed: "r", hovered: false, style: .blob, shapeMode: .status)
        #expect(abs(resting.up - CGFloat(max(pill.up, round.up) + Theme.yourTurnBounceHeight) * size) < 0.000_1)
        #expect(abs(resting.down - CGFloat(max(pill.down, round.down)) * size) < 0.000_1)
        let hovered = FaceReach.session(status: turn, seed: "r", hovered: true, style: .blob, shapeMode: .status)
        #expect(hovered == FaceReach.blob(Theme.yourTurnShapes.0, faceSize: size, peakScale: 1))
        let seedShape = FaceIdentity(seed: "r").shape
        let identity = FaceReach.session(status: turn, seed: "r", hovered: false, style: .blob, shapeMode: .identity)
        #expect(abs(identity.up - CGFloat(FaceReach.extent(of: seedShape).up + Theme.yourTurnBounceHeight) * size) < 0.000_1)
    }

    private static func elementCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { _ in count += 1 }
        return count
    }
}
