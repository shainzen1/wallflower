import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import AgentOverview

/// The glow behind a face follows its silhouette: it swaps and morphs with the body on the body's
/// clock, swells with every your-turn hop, breathes visibly and rests steady at its rest level.
@Suite("Shaped halo: follows the body, swells with the hop, breathes")
@MainActor
struct ShapedHaloTests {
    private let turn = FaceStatus.yourTurn(since: Date())
    private let size = Theme.faceSize

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private struct Layers {
        let halo: CAShapeLayer
        let haloHost: CALayer
        let face: CALayer
        let scaler: CALayer
        let body: CAShapeLayer
    }

    private func layers(of root: CALayer) throws -> Layers {
        let haloHost = try #require(root.sublayers?[0].sublayers?.first?.sublayers?.first)
        let halo = try #require(haloHost.sublayers?.first as? CAShapeLayer)
        let face = try #require(root.sublayers?[2].sublayers?.last)
        let scaler = try #require(face.sublayers?.first?.sublayers?.first)
        let body = try #require(scaler.sublayers?.first as? CAShapeLayer)
        return Layers(halo: halo, haloHost: haloHost, face: face, scaler: scaler, body: body)
    }

    /// The parts of a group animating `keyPath`.
    private func parts(_ animation: CAAnimation?, keyPath: String) -> [CAKeyframeAnimation] {
        ((animation as? CAAnimationGroup)?.animations ?? []).compactMap { $0 as? CAKeyframeAnimation }.filter { $0.keyPath == keyPath }
    }

    /// The control points of an animation's timing curves (custom curves are new objects every time).
    private func curves(_ animation: CAKeyframeAnimation) -> [[Float]] {
        (animation.timingFunctions ?? []).map { function in
            (0..<4).flatMap { index -> [Float] in
                var point: [Float] = [0, 0]
                function.getControlPoint(at: index, values: &point)
                return point
            }
        }
    }

    private func numbers(_ values: [Any]?) -> [Double] {
        (values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    }

    private func config(_ status: FaceStatus, seed: String = "glow", shapeMode: Theme.BlobShapeMode = .status) -> FaceConfiguration {
        FaceConfiguration(identity: FaceIdentity(seed: seed), mode: .status(status), size: size, filter: .none, blobShapeMode: shapeMode, colorMode: .status)
    }

    private func tree(_ config: FaceConfiguration) -> (BlobLayerTree, CALayer) {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let tree = BlobLayerTree(root: root)
        tree.apply(config)
        return (tree, root)
    }

    private func glow(_ shape: BlobShape, restScale: Double = 1) -> CGPath {
        BlobHalo.profile(for: BlobBody(shape: shape), restScale: restScale).path(size: size)
    }

    @Test("The glow swaps with the body: the same keyframe times, curves and start, on the scaled silhouettes")
    func swapsWithBody() throws {
        guard !reduceMotion else { return }
        let (_, root) = tree(config(turn))
        let l = try layers(of: root)
        let body = try #require(l.body.animation(forKey: "loop.swap") as? CAKeyframeAnimation)
        let halo = try #require(l.halo.animation(forKey: "loop.swap") as? CAKeyframeAnimation)
        #expect(halo.keyPath == "shadowPath")
        #expect(halo.keyTimes == body.keyTimes && halo.timingFunctions == body.timingFunctions)
        #expect(halo.duration == body.duration && halo.repeatCount == .infinity)
        #expect(abs(halo.beginTime - body.beginTime) < 0.01, "one clock for body and glow")
        let values = try #require(halo.values as? [CGPath])
        #expect(values.first == l.halo.shadowPath && values.first == glow(.pill), "it starts on the resting glow")
        #expect(values[1] == glow(Theme.yourTurnShapes.1), "and swaps to the round's")
    }

    @Test("The glow swells with every hop, in step with it, and only follows the hop in identity shape mode")
    func swellsWithHop() throws {
        guard !reduceMotion else { return }
        for shapeMode in [Theme.BlobShapeMode.status, .identity] {
            let (_, root) = tree(config(turn, shapeMode: shapeMode))
            let l = try layers(of: root)
            let bounce = try #require(l.scaler.animation(forKey: "loop.bounce"))
            let swell = try #require(l.halo.animation(forKey: "loop.haloSwell") as? CAAnimationGroup)
            #expect(abs(swell.beginTime - bounce.beginTime) < 0.01 && swell.duration == bounce.duration && swell.repeatCount == .infinity)
            let swap = BlobShapeSwap(alternate: nil)
            let parts = (swell.animations ?? []).compactMap { $0 as? CAKeyframeAnimation }
            #expect(parts.map(\.beginTime) == swap.swapTimes, "one swell per hop")
            for part in parts {
                #expect(part.keyPath == "transform.scale" && part.isAdditive)
                let values = (part.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
                #expect(values.first == 0 && values.last == 0 && abs((values.max() ?? 0) - (Theme.haloHopSwell - 1)) < 0.000_001)
                // Fullest on the landing squash: the hop's air time plus the squash's rise.
                let peak = (part.keyTimes?[1].doubleValue ?? 0) * part.duration
                #expect(abs(peak - (Theme.yourTurnBounceDuration + Theme.yourTurnSquashDuration * 0.4)) < 0.000_1)
                #expect(part.duration < swap.hold + swap.duration, "back to rest before the next hop")
            }
            #expect((l.halo.animation(forKey: "loop.swap") == nil) == (shapeMode == .identity))
        }
    }

    @Test("The glow lifts with every your-turn hop: the body's lift values, curves, beat, begin time and period, no squash")
    func liftsWithHop() throws {
        guard !reduceMotion else { return }
        for shapeMode in [Theme.BlobShapeMode.status, .identity] {
            let (_, root) = tree(config(turn, shapeMode: shapeMode))
            let l = try layers(of: root)
            let bounce = try #require(l.scaler.animation(forKey: "loop.bounce"))
            let lift = try #require(l.haloHost.animation(forKey: "loop.haloLift") as? CAAnimationGroup)
            #expect(lift.beginTime == bounce.beginTime, "one begin time, so body and glow leave the ground together")
            #expect(lift.duration == bounce.duration && lift.repeatCount == bounce.repeatCount && lift.timeOffset == bounce.timeOffset)
            let bodyLifts = parts(bounce, keyPath: "transform.translation.y")
            let glowLifts = parts(lift, keyPath: "transform.translation.y")
            #expect(glowLifts.count == bodyLifts.count && !glowLifts.isEmpty, "one lift per hop")
            for (glow, body) in zip(glowLifts, bodyLifts) {
                #expect(numbers(glow.values) == numbers(body.values) && abs((numbers(glow.values).max() ?? 0) - 3) < 0.000_1, "the same 3 pt")
                #expect(glow.keyTimes == body.keyTimes && glow.timingFunctions == body.timingFunctions)
                #expect(glow.beginTime == body.beginTime && glow.duration == body.duration && glow.isAdditive && body.isAdditive)
            }
            #expect(lift.animations?.count == glowLifts.count, "no squash on the glow: it stays on the body")
            #expect(!parts(bounce, keyPath: "transform.scale.y").isEmpty, "the body still squashes")
            #expect(l.halo.animation(forKey: "loop.haloSwell") != nil, "the swell stays, on the glow itself")
            #expect(CATransform3DIsIdentity(l.haloHost.transform), "only the presentation lifts; the model stays on the ground")
        }
    }

    @Test("The glow lifts with the attention hop: the hop's lift on the same clock, without the squash")
    func liftsWithAttentionHop() throws {
        guard !reduceMotion else { return }
        var config = config(.needsInput(kind: .question))
        let (tree, root) = tree(config)
        let l = try layers(of: root)
        #expect(l.haloHost.animation(forKey: "oneshot.hopLift") == nil, "no hop without a token change")
        config.attentionToken += 1
        tree.apply(config)
        let hop = try #require(l.face.animation(forKey: "oneshot.hop"))
        let glow = try #require(l.haloHost.animation(forKey: "oneshot.hopLift") as? CAKeyframeAnimation)
        let body = try #require(parts(hop, keyPath: "transform.translation.y").first)
        #expect(glow.keyPath == "transform.translation.y" && glow.isAdditive)
        #expect(numbers(glow.values) == numbers(body.values) && abs((numbers(glow.values).max() ?? 0) - size * Theme.hopHeight) < 0.000_1)
        #expect(glow.keyTimes == body.keyTimes && curves(glow) == curves(body))
        #expect(glow.duration == body.duration && glow.beginTime == body.beginTime + hop.beginTime, "the same clock as the face's hop")
        #expect(parts(hop, keyPath: "transform.scale.y").count == 1, "the squash stays on the body")
    }

    @Test("A hovered face's glow rests with it and picks the loop up again after the hover")
    func hoverSettles() throws {
        guard !reduceMotion else { return }
        var config = config(turn)
        let (tree, root) = tree(config)
        let l = try layers(of: root)
        config.hovered = true
        tree.apply(config)
        #expect(l.halo.animation(forKey: "loop.swap") == nil && l.halo.animation(forKey: "loop.haloSwell") == nil)
        #expect(l.haloHost.animation(forKey: "loop.haloLift") == nil, "the glow lands with the body")
        #expect(CATransform3DIsIdentity(l.haloHost.transform))
        #expect(l.halo.shadowPath == glow(.pill), "the resting glow, not stretched")
        config.hovered = false
        tree.apply(config)
        #expect(l.halo.animation(forKey: "loop.swap") != nil && l.halo.animation(forKey: "loop.haloSwell") != nil)
        #expect(l.haloHost.animation(forKey: "loop.haloLift")?.beginTime == l.scaler.animation(forKey: "loop.bounce")?.beginTime)
    }

    @Test("A status change morphs the glow with the body: the same delay and duration, to the new rest scale")
    func morphsWithBody() throws {
        guard !reduceMotion else { return }
        var config = config(turn)
        let (tree, root) = tree(config)
        let l = try layers(of: root)
        config.mode = .status(.needsInput(kind: .question))
        tree.apply(config)
        let body = try #require(l.body.animation(forKey: "morph") as? CAKeyframeAnimation)
        let halo = try #require(l.halo.animation(forKey: "morph") as? CAKeyframeAnimation)
        #expect(halo.keyPath == "shadowPath" && halo.keyTimes == body.keyTimes && halo.duration == body.duration)
        #expect(l.halo.shadowPath == glow(Theme.blobNeedsInputShape, restScale: Theme.attentionScale), "around the bigger waiting body")
        #expect(l.halo.animation(forKey: "loop.swap") == nil)
        #expect(l.halo.animation(forKey: "loop.haloPulse") != nil, "amber pulses with the grow")

        // Leaving every halo: the glow keeps its silhouette while it fades out.
        let before = l.halo.shadowPath
        config.mode = .status(.idle(since: Date()))
        tree.apply(config)
        #expect(l.haloHost.opacity == 0 && l.halo.shadowPath == before)
    }

    @Test("The breath swings from 0.4 of the peak to the peak in 1.8 s; the glow rests steady at its rest level")
    func breath() throws {
        #expect(Theme.doneHaloPulse == BreathLoop(scale: 0.4, period: 1.8) && Theme.yourTurnHaloPulse == Theme.doneHaloPulse)
        let halo = BlobHalo.yourTurn(color: Theme.yourTurnColor)
        let loop = BlobAnimations.haloBreath(halo.unit, breath: Theme.yourTurnHaloPulse, phase: 0)
        let values = (loop.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        #expect(values == [Theme.haloBreathLow, 1, Theme.haloBreathLow] && loop.duration == 1.8 && loop.repeatCount == .infinity)
        #expect(loop.timingFunctions?.allSatisfy { $0 == CAMediaTimingFunction(name: .easeInEaseOut) } == true, "the breath's ease, close to a sine")
        // The glow's model level is its rest (what Reduce Motion shows without loops); the host carries the peak.
        let (_, root) = tree(config(turn))
        let l = try layers(of: root)
        #expect(l.halo.opacity == Float(halo.restFraction) && l.haloHost.opacity == Float(Theme.yourTurnHaloOpacity))
        #expect(Theme.yourTurnHaloOpacity < Theme.attentionHaloOpacity)
    }
}
