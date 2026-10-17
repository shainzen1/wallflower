import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import AgentOverview

/// Every face stays in its row: the halo inside its cell and the capsule, the bodies `Theme.rowBodyGap`
/// apart under magnification and at the top of a grow, the action star clear of the divider and the end.
@Suite("Containment: halo in its row, bodies apart under magnification, star clear of the divider")
@MainActor
struct ContainmentTests {
    private let question = FaceStatus.needsInput(kind: .question)
    private let permission = FaceStatus.needsInput(kind: .permission)
    private let idle = FaceStatus.idle(since: Date())

    // MARK: Halo

    /// Every silhouette a glow can take: the halo programs' bodies at their rest scale, and the
    /// your-turn swap's other shape.
    private func haloProfiles() -> [(name: String, profile: BlobProfile)] {
        var profiles: [(String, BlobProfile)] = []
        for status in [question, permission, .justFinished, .yourTurn(since: Date())] {
            let program = BlobProgramBuilder.program(for: .status(status), identity: FaceIdentity(seed: "h"), bodyOverride: nil, shapeMode: .status, activity: .thinking, colorMode: .status, projectKey: nil)
            guard program.halo != nil else { continue }
            profiles.append(("\(status)", BlobHalo.profile(for: program.body, restScale: program.restScale)))
            if let alternate = program.swap?.alternate {
                profiles.append(("\(status) swapped", BlobHalo.profile(for: alternate, restScale: program.restScale)))
            }
        }
        return profiles
    }

    @Test("The glow is spent at the row boundary and inside the capsule, swell included, on every silhouette")
    func haloRadius() {
        let outer = CGFloat(BlobHalo.outerRadius) * Theme.faceSize
        #expect(outer <= Theme.rowPitch / 2 + 0.000_001, "inside the row (\(outer))")
        #expect(outer <= Theme.capsuleWidth / 2 - 2 + 0.000_001, "inside the capsule's side with 2 pt to spare (\(outer))")
        #expect(abs(outer - Theme.haloOuterRadius) < 0.000_001 && abs(outer - 26) < 0.000_001, "26 pt with today's constants")
        let profiles = haloProfiles()
        #expect(profiles.count == 5, "question, permission, done, your turn and its swap")
        let size = Theme.faceSize
        let centre = size / 2
        let tail = CGFloat(BlobHalo.tail) * size
        for (name, profile) in profiles {
            #expect(BlobHalo.extent(of: profile) <= BlobHalo.outerRadius + 0.000_001, "\(name)")
            // The drawn curve, not only the samples: its farthest point plus the tail, swollen.
            let box = profile.path(size: size).boundingBoxOfPath
            let reach = max(box.maxX - centre, centre - box.minX, box.maxY - centre, centre - box.minY)
            #expect((reach + tail) * CGFloat(Theme.haloHopSwell) <= outer + 0.01, "\(name): \(reach) + \(tail)")
        }
        // A Gaussian rim two sigmas beyond the fill keeps about 2 % alpha: two lit rows keep a dark gap.
        let spent = 0.5 * erfc(Theme.haloTailSigmas / 2.squareRoot())
        #expect(spent * Theme.attentionHaloOpacity < 0.02, "\(spent)")
        #expect(BlobHalo.done.color == Theme.justFinishedColor, "the mint halo is the same layer, the same rule")
    }

    /// A cubic Bezier timing curve (control points `c1`, `c2`) evaluated at progress `x`, as Core Animation does.
    private func timing(_ c1: (Double, Double), _ c2: (Double, Double), at x: Double) -> Double {
        func bezier(_ a: Double, _ b: Double, _ t: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var low = 0.0, high = 1.0
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if bezier(c1.0, c2.0, mid) < x { low = mid } else { high = mid }
        }
        return bezier(c1.1, c2.1, (low + high) / 2)
    }

    @Test("A lifted glow rises inside its row's clip; what the clip trims at the top of a hop is a faint rim")
    func liftedGlowInClip() {
        let size = Theme.faceSize
        let sigma = CGFloat(Theme.haloSoftness) * size
        let edge = Theme.rowPitch / 2
        let centre = size / 2
        /// The glow's reach above the face centre (fill only) for a silhouette at a rest scale.
        func fillTop(_ shape: BlobShape, restScale: Double) -> CGFloat {
            BlobHalo.profile(for: BlobBody(shape: shape), restScale: restScale).path(size: size).boundingBoxOfPath.maxY - centre
        }
        /// The Gaussian rim's alpha `distance` beyond the fill (half at the fill's edge).
        func rim(_ distance: CGFloat) -> Double { 0.5 * erfc(Double(distance / sigma) / 2.squareRoot()) }

        // Your turn: the lift peaks early in the hop, while the swell is still on its way up (ease in and out).
        let liftPeak = Theme.yourTurnBounceUpFraction * Theme.yourTurnBounceDuration
        let rise = Theme.yourTurnBounceDuration + Theme.yourTurnSquashDuration * 0.4
        let swell = 1 + (Theme.haloHopSwell - 1) * timing((0.42, 0), (0.58, 1), at: liftPeak / rise)
        let lift = CGFloat(Theme.yourTurnBounceHeight) * size
        for shape in [Theme.yourTurnShapes.0, Theme.yourTurnShapes.1] {
            let top = fillTop(shape, restScale: 1) * CGFloat(swell) + lift
            let trimmed = rim(edge - top) * Theme.yourTurnHaloOpacity
            print("containment: your-turn \(shape) glow at the top of the hop: fill \(top) pt, \(trimmed) alpha left at the row's edge")
            #expect(top < edge, "the fill itself never reaches the clip (\(shape): \(top))")
            #expect(trimmed < 0.08, "the clip only trims a faint rim (\(shape): \(trimmed))")
        }
        // The attention hop: a bigger hop (5 pt), no swell. The capped drop's fill comes within a fraction
        // of a point of the row's edge, so the clip trims about half the rim there; in the panel the hop
        // only plays as a face starts waiting, while its glow is still fading in, so what is trimmed is faint.
        let drop = fillTop(Theme.blobNeedsInputShape, restScale: Theme.attentionScale) + CGFloat(Theme.hopHeight) * size
        let fadeIn = timing((0.42, 0), (0.58, 1), at: Theme.hopUpFraction * Theme.hopDuration / Theme.haloFadeDuration)
        let dropTrimmed = rim(edge - drop) * Theme.attentionHaloOpacity * Theme.attentionHaloRestFraction * fadeIn
        print("containment: waiting glow at the top of the attention hop: fill \(drop) pt, \(dropTrimmed) alpha left at the row's edge")
        #expect(drop < edge, "the fill stays inside the row (\(drop))")
        #expect(dropTrimmed < 0.06, "a faint rim, the glow is still fading in (\(dropTrimmed))")
    }

    @Test("The glow follows the silhouette: the body scaled by haloScale where it fits, held at the cap elsewhere")
    func haloFollowsShape() {
        let pill = BlobHalo.profile(for: BlobBody(shape: .pill), restScale: 1)
        let body = BlobBody(shape: .pill).profile
        let cap = BlobHalo.fillCap
        for (glow, radius) in zip(pill.radii, body.radii) {
            #expect(abs(glow - min(radius * Theme.haloScale, cap)) < 0.000_001)
        }
        // The pill's glow is a pill too: its top the scaled body's, well inside the cap (not a circle).
        let top = BlobProfile.sampleCount / 4
        #expect(pill.radii[top] < cap - 0.04, "not a circle")
        #expect(abs(pill.radii[top] - body.radii[top] * Theme.haloScale) < 0.000_001, "the top is the body scaled up")
        #expect(pill.radii[top] > body.radii[top] + 0.06, "a visible band above the pill (\((pill.radii[top] - body.radii[top]) * 44) pt)")
        // A waiting face's glow takes its rest scale too, so it sits around the bigger body.
        let drop = BlobBody(shape: Theme.blobNeedsInputShape)
        let rest = BlobHalo.profile(for: drop, restScale: Theme.attentionScale)
        let plain = BlobHalo.profile(for: drop, restScale: 1)
        #expect(zip(rest.radii, plain.radii).allSatisfy { $0 >= $1 } && rest.radii != plain.radii)
        #expect(pill.radii.count == BlobProfile.sampleCount, "the body's sample angles, so it morphs with the body")
    }

    @Test("The layer tree clips the halo to its row cell and the burst to the capsule width, outside the magnification")
    func layerClips() {
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: Theme.faceSize, height: Theme.faceSize)
        let tree = BlobLayerTree(root: root)
        var config = FaceConfiguration(identity: FaceIdentity(seed: "clip"), mode: .status(.justFinished), size: Theme.faceSize, filter: .none)
        tree.apply(config)
        config.magnify = MagnifyState(scale: 1.28, dx: -3, dy: 3)
        tree.apply(config)
        let sublayers = root.sublayers ?? []
        #expect(sublayers.count == 3, "halo clip, burst clip, magnify")
        let haloClip = sublayers[0]
        let burstClip = sublayers[1]
        let magnify = sublayers[2]
        #expect(haloClip.masksToBounds && burstClip.masksToBounds && !magnify.masksToBounds)
        #expect(haloClip.bounds.size == CGSize(width: Theme.capsuleWidth, height: Theme.rowPitch), "the row's cell")
        #expect(burstClip.bounds.width == Theme.capsuleWidth, "the capsule's width")
        for clip in [haloClip, burstClip] {
            #expect(clip.position == CGPoint(x: Theme.faceSize / 2, y: Theme.faceSize / 2) && CATransform3DIsIdentity(clip.transform), "centred on the face, never moved")
        }
        let follow = haloClip.sublayers?.first
        let t = follow?.transform ?? CATransform3DIdentity
        #expect(t.m11 == 1 && t.m22 == 1 && t.m41 == -3 && t.m42 == -3, "the halo drifts with the face but never scales")
        #expect(burstClip.sublayers?.first?.transform.m11 == 1.28, "the burst magnifies with the face")
        #expect(magnify.transform.m11 == 1.28)
        // The burst's farthest dot would pass the capsule's side without the clip (so the clip is load-bearing).
        let reach = Theme.doneBurstDistance * Theme.faceSize + Theme.doneBurstDotSize * Theme.faceSize / 2
        #expect(reach > Theme.capsuleWidth / 2 - 2, "documents why the burst is clipped (\(reach))")
    }

    @Test("The halo, its hosts and the burst clip sit on the face centre, the glow within the outer radius, no drift at rest", arguments: [FaceStatus.justFinished, .yourTurn(since: Date())])
    func haloCentred(status: FaceStatus) throws {
        let size = Theme.faceSize
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let tree = BlobLayerTree(root: root)
        var config = FaceConfiguration(identity: FaceIdentity(seed: "centre"), mode: .status(.working), size: size, filter: .none)
        config.colorMode = .status
        tree.apply(config)
        config.mode = .status(status)
        tree.apply(config)
        let centre = CGPoint(x: size / 2, y: size / 2)
        let sublayers = try #require(root.sublayers)
        let haloClip = sublayers[0]
        let haloFollow = try #require(haloClip.sublayers?.first)
        let haloHost = try #require(haloFollow.sublayers?.first)
        let halo = try #require(haloHost.sublayers?.first as? CAShapeLayer)
        let burstClip = sublayers[1]
        let burstMagnify = try #require(burstClip.sublayers?.first)
        for (name, layer) in [("haloClip", haloClip), ("haloFollow", haloFollow), ("haloHost", haloHost), ("halo", halo), ("burstClip", burstClip), ("burstMagnify", burstMagnify)] {
            let own = root.convert(CGPoint(x: layer.bounds.midX, y: layer.bounds.midY), from: layer)
            #expect(abs(own.x - centre.x) < 0.000_1 && abs(own.y - centre.y) < 0.000_1, "\(name) centre at \(own), face centre \(centre)")
        }
        #expect(CATransform3DIsIdentity(haloFollow.transform), "no drift while nothing is hovered")
        #expect(halo.bounds.size == CGSize(width: size, height: size), "a face square, so the swell scales about the face centre")
        #expect(halo.anchorPoint == CGPoint(x: 0.5, y: 0.5) && CATransform3DIsIdentity(halo.transform) && CATransform3DIsIdentity(haloHost.transform))
        // The glow is the shadow of the scaled silhouette, centred on the face and spent inside the outer radius.
        #expect(halo.fillColor == nil && halo.path == nil && halo.shadowOpacity == 1 && halo.shadowOffset == .zero, "only the shadow shows")
        #expect(abs(halo.shadowRadius - size * Theme.haloSoftness) < 0.000_1)
        let path = try #require(halo.shadowPath)
        let box = path.boundingBoxOfPath
        let glowCentre = root.convert(CGPoint(x: box.midX, y: box.midY), from: halo)
        #expect(abs(glowCentre.x - centre.x) < 0.01 && abs(glowCentre.y - centre.y) < 0.01, "the glow's centre at \(glowCentre)")
        let reach = max(box.width, box.height) / 2 + halo.shadowRadius * Theme.haloTailSigmas
        #expect(reach * Theme.haloHopSwell <= Theme.haloOuterRadius + 0.01, "the glow's extent \(reach) inside the outer radius")
    }

    // MARK: Hover takes over the attention scale

    @Test("A hovered waiting face rests at 1 with the grow paused; the box clamp is the plain one")
    func takeover() {
        let program = BlobProgramBuilder.program(for: .status(question), identity: FaceIdentity(seed: "t"), bodyOverride: nil, shapeMode: .status, activity: .thinking, colorMode: .status, projectKey: nil)
        var config = FaceConfiguration(identity: FaceIdentity(seed: "t"), mode: .status(question), size: Theme.faceSize, filter: .none)
        #expect(!BlobLayerTree.takesOverAttention(config, program: program))
        config.hovered = true
        #expect(BlobLayerTree.takesOverAttention(config, program: program))
        config.hoverEffect = .stretch
        #expect(!BlobLayerTree.takesOverAttention(config, program: program), "only the magnify effect takes over")
        let idleProgram = BlobProgramBuilder.program(for: .status(idle), identity: FaceIdentity(seed: "t"), bodyOverride: nil, shapeMode: .status, activity: .thinking, colorMode: .status, projectKey: nil)
        config.hoverEffect = .magnify
        #expect(!BlobLayerTree.takesOverAttention(config, program: idleProgram), "nothing to take over on an idle face")

        let hovered = FaceReach.session(status: question, seed: "t", hovered: true)
        let resting = FaceReach.session(status: question, seed: "t", hovered: false)
        #expect(hovered.boxScale == 1 && abs(resting.boxScale - Theme.attentionScale * Theme.attentionGrowScale) < 0.000_001)
        #expect(MagnifyState.maxScale(faceSize: Theme.faceSize, restScale: hovered.boxScale) == MagnifyState.maxScale(faceSize: Theme.faceSize))
        let t = BlobLayerTree.restTransform(1.08)
        #expect(t.m11 == 1.08 && t.m22 == 1.08 && t.m33 == 1.08, "z in step, so the additive loops add to the rest scale")
    }

    @Test("The reach mirrors the program each status gets: silhouette, rest scale, grow and loops")
    func reachMatchesPrograms() {
        let statuses: [FaceStatus] = [question, permission, .working, idle, .justFinished, .ended]
        for status in statuses {
            let program = BlobProgramBuilder.program(for: .status(status), identity: FaceIdentity(seed: "r"), bodyOverride: nil, shapeMode: .status, activity: .thinking, colorMode: .status, projectKey: nil)
            var peak = FaceReach.peakScale(restScale: program.restScale, grow: program.grow, bodyLoop: program.bodyLoop)
            if program.bounce { peak = max(peak, Theme.blobBounceScale) }
            let extent = FaceReach.extent(of: program.body.shape)
            let reach = FaceReach.session(status: status, seed: "r", hovered: false, shapeMode: .status)
            #expect(abs(reach.up - CGFloat(extent.up * peak) * Theme.faceSize) < 0.000_1, "\(status)")
            #expect(abs(reach.down - CGFloat(extent.down * peak) * Theme.faceSize) < 0.000_1, "\(status)")
        }
        // The top of a grow: rest 1.08 plus the grow 0.12 plus the pulse 0.04.
        let waiting = FaceReach.session(status: question, seed: "r", hovered: false)
        let drop = FaceReach.extent(of: Theme.blobNeedsInputShape)
        #expect(abs(waiting.up - CGFloat(drop.up * 1.24) * Theme.faceSize) < 0.000_1)
        let star = FaceReach.extent(of: .star)
        #expect(abs(star.up - Theme.blobRadius * 1.04) < 0.002 && abs(star.down - Theme.blobRadius * 1.04) < 0.002, "the star's points at 1.04 r")
    }

    // MARK: Geometry

    /// One sweep of the pointer over a column: every body's top and bottom for every pointer position.
    private struct Sweep {
        var minGap = CGFloat.infinity
        var minDividerGap = CGFloat.infinity
        var minEndGap = CGFloat.infinity
        var hoveredWaitingMax: CGFloat = 0
        var starMax: CGFloat = 0
    }

    private func sweep(statuses: [FaceStatus], actions: Int) -> Sweep {
        let rows = statuses.count
        let count = rows + actions
        let height = Theme.capsuleHeight(rows: rows, actions: actions)
        let centres = (0..<count).map { PanelModel.slotCenterY(slot: $0, rows: rows, actions: actions) }
        var result = Sweep()
        let star = ActionFace(phase: .resting)
        func column(hovered: Int?) -> MagnifyColumn {
            PanelModel.magnifyColumn(slots: 0...(count - 1), rows: rows, actions: actions) { slot in
                slot < rows
                    ? FaceReach.session(status: statuses[slot], seed: "s\(slot)", hovered: slot == hovered)
                    : FaceReach.action(slot == hovered ? ActionFace(phase: .hovered) : star)
            }
        }
        func measure(_ column: MagnifyColumn, states: [MagnifyState], hovered: Int?) {
            for (index, state) in states.enumerated() {
                let face = column.faces[index]
                let top = face.centerY + state.dy - state.scale * face.reach.up
                let bottom = face.centerY + state.dy + state.scale * face.reach.down
                if index == 0 { result.minEndGap = min(result.minEndGap, top - column.top) }
                if index == count - 1 { result.minEndGap = min(result.minEndGap, column.bottom - bottom) }
                for divider in column.dividers {
                    if face.centerY < divider { result.minDividerGap = min(result.minDividerGap, divider - bottom) }
                    if face.centerY > divider { result.minDividerGap = min(result.minDividerGap, top - divider) }
                }
                if index < count - 1 {
                    let next = column.faces[index + 1]
                    let nextState = states[index + 1]
                    let nextTop = next.centerY + nextState.dy - nextState.scale * next.reach.up
                    let crossesDivider = column.dividers.contains { $0 > face.centerY && $0 < next.centerY }
                    if !crossesDivider { result.minGap = min(result.minGap, nextTop - bottom) }
                }
                if index == hovered, index < rows, statuses[index].isNeedsInput {
                    result.hoveredWaitingMax = max(result.hoveredWaitingMax, state.scale)
                }
                if index >= rows { result.starMax = max(result.starMax, state.scale) }
            }
        }
        // At rest (no pointer), every waiting face at the top of its grow.
        let rest = column(hovered: nil)
        measure(rest, states: Array(repeating: .identity, count: count), hovered: nil)
        var y: CGFloat = 0
        while y <= height {
            let hovered = centres.indices.min { abs(centres[$0] - y) < abs(centres[$1] - y) }
            let column = column(hovered: hovered)
            for x in [-120, 0, Theme.capsuleWidth / 2, Theme.capsuleWidth] {
                let pointer = CGPoint(x: x, y: y)
                measure(column, states: column.states(pointer: pointer), hovered: hovered)
            }
            y += 0.25
        }
        return result
    }

    @Test("No two bodies come closer than the gap, with the pointer anywhere and every waiting face at the top of its grow")
    func bodiesStayApart() {
        let layouts: [([FaceStatus], Int)] = [
            ([question, idle, question, question, idle, .working], 2),
            ([question, question, question], 0),
            ([permission, question, idle, permission], 1),
            ([idle, .working, .justFinished, idle], 3),
            ([.yourTurn(since: Date()), .yourTurn(since: Date()), question, .yourTurn(since: Date())], 1),
            ([question], 1),
            ([], 3),
        ]
        var overall = CGFloat.infinity
        for (statuses, actions) in layouts {
            let result = sweep(statuses: statuses, actions: actions)
            #expect(result.minGap >= Theme.rowBodyGap - 0.000_1, "\(statuses) + \(actions) actions: \(result.minGap)")
            #expect(result.minEndGap >= Theme.rowBodyGap - 0.000_1, "capsule ends: \(result.minEndGap)")
            if actions > 0, !statuses.isEmpty {
                #expect(result.minDividerGap >= Theme.rowBodyGap - 0.000_1, "divider: \(result.minDividerGap)")
            }
            if statuses.contains(where: \.isNeedsInput) {
                #expect(result.hoveredWaitingMax >= 1.2, "the hovered amber face still magnifies: \(result.hoveredWaitingMax)")
            }
            overall = min(overall, result.minGap)
        }
        print("containment: minimum body gap \(overall) pt")
        let solo = sweep(statuses: [question], actions: 0)
        print("containment: hovered waiting face reaches \(solo.hoveredWaitingMax); between waiting neighbours \(sweep(statuses: [question, question, question], actions: 0).hoveredWaitingMax)")
    }

    @Test("The action star's clamp comes from the divider line and the capsule's end")
    func starClamp() {
        // One live row, one action: the star's room above is the divider line, below the capsule's end.
        let column = PanelModel.magnifyColumn(slots: 0...1, rows: 1, actions: 1) { slot in
            slot == 0 ? FaceReach.session(status: idle, seed: "i", hovered: false) : FaceReach.action(ActionFace(phase: .hovered))
        }
        let star = column.faces[1]
        let pointer = CGPoint(x: Theme.capsuleWidth / 2, y: star.centerY)
        let up = column.roomAbove(1, pointer: pointer)
        let down = column.roomBelow(1, pointer: pointer)
        let divider = PanelModel.slotCenterY(slot: 0, rows: 1, actions: 1) + Theme.rowPitch / 2 + Theme.dividerHeight / 2
        #expect(abs(up - (star.centerY - divider - Theme.rowBodyGap)) < 0.000_001)
        #expect(abs(down - (Theme.capsuleEndPadding + Theme.rowPitch / 2 - Theme.rowBodyGap)) < 0.000_001)
        let clamp = min(up, down) / star.reach.up
        print("containment: star clamp \(clamp) (room above \(up) pt, below \(down) pt, half extent \(star.reach.up) pt)")
        #expect(clamp > 1.4 && clamp < 1.5, "29 pt over 19.7 pt with today's constants: \(clamp)")
        let state = column.state(1, pointer: pointer)
        #expect(state.scale <= clamp && abs(state.scale - Theme.magnifyMax) < 0.000_001, "the clamp is above magnifyMax, so the star keeps its full magnification")
        // Two stars next to each other share the pitch like any two faces.
        let pair = sweep(statuses: [idle], actions: 2)
        #expect(pair.minGap >= Theme.rowBodyGap - 0.000_1 && pair.starMax > 1.2, "\(pair.minGap), \(pair.starMax)")
    }
}
