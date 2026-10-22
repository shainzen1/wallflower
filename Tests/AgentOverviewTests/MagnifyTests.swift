import CoreGraphics
import QuartzCore
import Foundation
import Testing
@testable import AgentOverview

@Suite("Dock-style magnification on hover")
struct MagnifyTests {
    private let pitch = Theme.rowPitch

    @Test("The falloff: full at the pointer, a little at one pitch, nearly nothing at two")
    func falloff() {
        #expect(MagnifyState.weight(distance: 0) == 1)
        #expect(abs(MagnifyState.scale(distance: 0) - Theme.magnifyMax) < 0.000_001)
        let one = MagnifyState.scale(distance: pitch)
        let two = MagnifyState.scale(distance: 2 * pitch)
        #expect(abs(one - (1 + (Theme.magnifyMax - 1) * exp(-pow(1 / 1.1, 2)))) < 0.000_001, "exp(-(d / spread)^2) with spread = 1.1 pitches")
        #expect(one > 1.1 && one < 1.15, "the neighbour grows a little (\(one))")
        #expect(two > 1 && two < 1.015, "two rows away stays at 1 (\(two))")
        #expect(MagnifyState.scale(distance: 3 * pitch) - 1 < 0.001)
        #expect(MagnifyState.at(offset: .zero, distance: 0) == MagnifyState(scale: Theme.magnifyMax, dx: 0, dy: 0), "no follow right on the centre")
        #expect(Theme.magnifySpread == 1.1 * pitch && Theme.magnifyMax == 1.28)
    }

    @Test("The clamp keeps a face inside the capsule width minus the margin, with its rest scale")
    func clamp() {
        let plain = MagnifyState.maxScale(faceSize: Theme.faceSize)
        #expect(abs(plain * Theme.faceSize - (Theme.capsuleWidth - Theme.magnifyMargin)) < 0.000_001)
        #expect(Theme.magnifyMax < plain, "a resting face at full magnification still fits")
        let waiting = MagnifyState.maxScale(faceSize: Theme.faceSize, restScale: Theme.attentionScale)
        #expect(waiting < Theme.magnifyMax, "a waiting face (bigger at rest) is clamped")
        let state = MagnifyState.at(offset: .zero, distance: 0, maxScale: waiting)
        #expect(abs(state.scale - waiting) < 0.000_001)
        #expect(abs(state.scale * Theme.attentionScale * Theme.faceSize - (Theme.capsuleWidth - Theme.magnifyMargin)) < 0.000_001)
        #expect(MagnifyState.at(offset: .zero, distance: 0, maxScale: 0.5).scale == 1, "the clamp never shrinks a face")
    }

    @Test("The follow leans toward the pointer: left when it is left, up when it is above, scaled by the falloff and the face size")
    func followDirection() {
        let left = MagnifyState.at(offset: CGPoint(x: -Theme.faceSize / 2, y: 0), distance: 0)
        #expect(left.dx == -Theme.followX && left.dy == 0, "full follow at the face's left rim, on the centre line")
        let right = MagnifyState.at(offset: CGPoint(x: 100, y: 0), distance: 0)
        #expect(right.dx == Theme.followX, "never more than followX")
        let above = MagnifyState.at(offset: CGPoint(x: 0, y: -pitch / 2), distance: pitch / 2)
        #expect(above.dy < 0 && above.dy > -Theme.followY, "up, weighted by the falloff at half a pitch")
        #expect(abs(above.dy - (-Theme.followY * MagnifyState.weight(distance: pitch / 2))) < 0.000_001)
        let below = MagnifyState.at(offset: CGPoint(x: 0, y: pitch), distance: pitch)
        #expect(below.dy > 0 && below.dy < above.magnitude(\.dy), "the row below the pointer leans up less than the half-pitch one")
        let hero = MagnifyState.at(offset: CGPoint(x: -100, y: 0), distance: 0, faceSize: 120, followReach: CGSize(width: 70, height: 60))
        #expect(abs(hero.dx - (-Theme.followX * 120 / Theme.faceSize)) < 0.000_001, "the follow scales with the face")
        let far = MagnifyState.at(offset: CGPoint(x: -20, y: 4 * pitch), distance: 4 * pitch)
        #expect(abs(far.dx) < 0.001 && abs(far.dy) < 0.001, "far faces do not move")
    }

    @Test("The layer transform scales about the centre and flips the top-left dy")
    func transform() {
        let state = MagnifyState(scale: 1.2, dx: -3, dy: 2)
        let t = state.transform
        #expect(t.m11 == 1.2 && t.m22 == 1.2 && t.m41 == -3 && t.m42 == -2)
        #expect(CATransform3DIsIdentity(MagnifyState.identity.transform))
        var config = FaceConfiguration(identity: FaceIdentity(seed: "m"), mode: .status(.working), size: 44, filter: .none)
        config.hovered = true
        #expect(config.hoverEffect == Theme.hoverEffect && !config.stretched, "magnify is the default; hovered alone stretches nothing")
        config.hoverEffect = .stretch
        #expect(config.stretched)
        config.magnify = state
        #expect(config != FaceConfiguration(identity: FaceIdentity(seed: "m"), mode: .status(.working), size: 44, filter: .none), "a magnify change reaches the layer tree")
    }

    @Test("The model magnifies from the pointer on the capsule, keeps it on the bulge, releases to identity outside")
    @MainActor
    func modelPointer() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        var idle = try TestSupport.fixtureRecord("idle-desktop")
        var busy = try TestSupport.fixtureRecord("busy-desktop")
        var waiting = try TestSupport.fixtureRecord("waiting-desktop")
        idle.pid = TestSupport.livePid
        busy.pid = TestSupport.otherLivePid
        waiting.pid = TestSupport.keeperPid
        store.reconcile(RegistryScanResult(records: [idle, busy, waiting], presentPids: [idle.pid, busy.pid, waiting.pid]))
        let model = PanelModel(store: store)
        #expect(model.hoverEffect == .magnify)
        let width = Theme.contentWidth + Theme.windowPadding
        let size = CGSize(width: width, height: model.capsuleHeight)
        #expect(model.pointer == nil && model.magnify(slot: 1) == .identity)

        let centre1 = model.slotCenterY(slot: 1)
        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2, y: centre1), in: size)
        #expect(model.pointer == CGPoint(x: Theme.capsuleWidth / 2, y: centre1), "capsule coordinates")
        #expect(model.hoveredRowIndex == 1)
        #expect(abs(model.magnify(slot: 1).scale - Theme.magnifyMax) < 0.000_001)
        #expect(model.magnify(slot: 1).dx == 0 && model.magnify(slot: 1).dy == 0)
        let neighbour = model.magnify(slot: 0)
        let waitingBox = MagnifyState.maxScale(faceSize: Theme.faceSize, restScale: Theme.attentionScale * Theme.attentionGrowScale)
        #expect(abs(neighbour.scale - min(MagnifyState.scale(distance: pitch), waitingBox)) < 0.000_001, "the waiting neighbour is clamped at the top of its grow")
        #expect(neighbour.dy > 0, "the row above leans down toward the pointer")
        #expect(model.magnify(slot: 2).dy < 0, "the row below leans up")
        #expect(model.magnify(slot: 7) == .identity, "no such slot")

        // A little left of the centre line, between rows 1 and 2: both lean left, row 1 more than row 0.
        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2 - 10, y: centre1 + pitch / 2), in: size)
        #expect(model.magnify(slot: 1).dx < 0 && model.magnify(slot: 2).dx < 0)
        #expect(abs(model.magnify(slot: 1).scale - model.magnify(slot: 2).scale) < 0.000_001, "halfway between two rows they match")
        #expect(model.magnify(slot: 1).dx < model.magnify(slot: 0).dx)

        // On the open bulge the pointer is kept (the hover stays), left of the capsule.
        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2, y: centre1), in: size)
        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth - 100, y: centre1), in: size)
        #expect(model.hoveredRowIndex == 1)
        #expect(model.pointer?.x == -100)
        #expect(model.magnify(slot: 1).dx == -Theme.followX, "leans fully toward the bulge")

        model.pointerMoved(to: nil, in: size)
        #expect(model.pointer == nil && model.magnify(slot: 1) == .identity, "release to identity")
        #expect(!model.isExpanded)

        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2, y: centre1), in: size)
        model.pointerMoved(to: CGPoint(x: 1, y: 1), in: size)
        #expect(model.pointer == nil, "transparent window area ends it")

        let stretch = PanelModel(store: store, hoverEffect: .stretch)
        stretch.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2, y: centre1), in: size)
        #expect(stretch.pointer != nil && stretch.magnify(slot: 1) == .identity, "the stretch effect never magnifies")
        #expect(stretch.hoveredRowIndex == 1)
        model.pointerMoved(to: CGPoint(x: width - Theme.capsuleWidth / 2, y: model.slotCenterY(slot: 0)), in: size)
        #expect(model.hoveredRowIndex == 0)
        #expect(model.magnify(slot: 0).scale >= 1.2, "the hovered waiting row takes the attention scale over and magnifies")
        #expect(model.magnify(slot: 1).scale < MagnifyState.scale(distance: pitch) + 0.000_001)
    }

    @Test("Launch arguments: the hover effect and the pointer glide; the playground cycles the effect")
    @MainActor
    func launchArguments() {
        #expect(LaunchArguments(["app", "--hover-effect", "stretch"]).hoverEffect == .stretch)
        #expect(LaunchArguments(["app", "--hover-effect", "none"]).hoverEffect == Theme.HoverEffect.none)
        #expect(LaunchArguments(["app", "--hover-effect", "magnify"]).hoverEffect == .magnify)
        #expect(LaunchArguments(["app", "--hover-effect", "wobble"]).hoverEffect == nil)
        #expect(LaunchArguments(["app"]).hoverEffect == nil && LaunchArguments(["app"]).pointerGlide == nil)
        let glide = LaunchArguments(["app", "--pointer-glide", "0,3,1.5"]).pointerGlide
        #expect(glide?.fromSlot == 0 && glide?.toSlot == 3 && glide?.duration == 1.5)
        #expect(LaunchArguments(["app", "--pointer-glide", "0,3"]).pointerGlide == nil)
        #expect(LaunchArguments(["app", "--pointer-glide", "0,3,0"]).pointerGlide == nil)
        #expect(Theme.HoverEffect.magnify.next == .stretch && Theme.HoverEffect.none.next == .magnify)

        let playground = PlaygroundModel(arguments: ["app"])
        #expect(playground.hoverEffect == FaceLook.hoverEffect && playground.look.hoverEffect == playground.hoverEffect)
        playground.cycleHoverEffect()
        #expect(playground.hoverEffect == FaceLook.hoverEffect.next)
        playground.heroPointerMoved(to: CGPoint(x: 60, y: 60))
        #expect(playground.heroPointer == CGPoint(x: 60, y: 60))
        playground.heroPointerMoved(to: nil)
        #expect(playground.heroPointer == nil)
        #expect(PlaygroundStatusRow.heroCentre(column: 1).x == PlaygroundView.heroSize * 1.5 + PlaygroundStatusRow.spacing)
    }
}

private extension MagnifyState {
    func magnitude(_ keyPath: KeyPath<MagnifyState, CGFloat>) -> CGFloat {
        abs(self[keyPath: keyPath])
    }
}
