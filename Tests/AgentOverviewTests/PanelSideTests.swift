import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import AgentOverview

/// The panel on the left screen edge: every horizontal rule is the right edge's, mirrored
/// (`PanelSide`), and the setting round-trips like the others.
@Suite("Panel side: the left edge mirrors the right edge's geometry")
@MainActor
struct PanelSideTests {
    private let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
    private let visible = NSRect(x: 0, y: 60, width: 2560, height: 1350)
    private let tolerance: CGFloat = 0.000_001

    // MARK: The mirror

    @Test("Every mirror is the identity on the right and its own inverse on the left")
    func mirrorHelpers() {
        let width: CGFloat = 300
        let rect = CGRect(x: 20, y: 5, width: 40, height: 10)
        #expect(PanelSide.right.mirror(x: 20, in: width) == 20)
        #expect(PanelSide.left.mirror(x: 20, in: width) == 280)
        #expect(PanelSide.left.mirror(x: PanelSide.left.mirror(x: 20, in: width), in: width) == 20)
        #expect(PanelSide.right.mirror(rect, in: width) == rect)
        #expect(PanelSide.left.mirror(rect, in: width) == CGRect(x: 240, y: 5, width: 40, height: 10))
        #expect(PanelSide.left.mirror(PanelSide.left.mirror(rect, in: width), in: width) == rect)
        #expect(PanelSide.left.mirror(dx: -7) == 7 && PanelSide.right.mirror(dx: -7) == -7)
        #expect(rect.applying(PanelSide.left.transform(in: width)) == PanelSide.left.mirror(rect, in: width))
        // The edge is at the far right of a right-side view and at x 0 of a left-side view.
        #expect(PanelSide.right.distanceFromEdge(x: 290, width: width) == 10)
        #expect(PanelSide.left.distanceFromEdge(x: 10, width: width) == 10)
        #expect(PanelSide.left.x(fromEdge: 10, width: width) == 10 && PanelSide.right.x(fromEdge: 10, width: width) == 290)
        #expect(PanelSide.default == .right)
    }

    // MARK: Placement

    @Test("Left placement: flush with the screen's left edge, growing rightward, the same height and offset")
    func placementFrame() {
        let right = PanelPlacement(edgeInset: 8, side: .right)
        let left = PanelPlacement(edgeInset: 8, side: .left)
        let screen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let visible = NSRect(x: -1920, y: 0, width: 1920, height: 1050)
        for offset: CGFloat in [0, 300, -5000] {
            let collapsedRight = right.frame(for: .collapsed, capsuleHeight: 140, offset: offset, screenFrame: screen, visibleFrame: visible)
            let collapsed = left.frame(for: .collapsed, capsuleHeight: 140, offset: offset, screenFrame: screen, visibleFrame: visible)
            let expanded = left.frame(for: .expanded(width: Theme.contentWidth), capsuleHeight: 140, offset: offset, screenFrame: screen, visibleFrame: visible)
            #expect(collapsed.minX == screen.minX)
            #expect(expanded.minX == screen.minX, "the window grows rightward, away from the edge")
            #expect(expanded.width == Theme.contentWidth + Theme.windowPadding)
            #expect(collapsed.minY == collapsedRight.minY && collapsed.size == collapsedRight.size, "only x changes")
            #expect(collapsedRight.maxX == screen.maxX)
        }
    }

    // MARK: Capsule

    @Test("Left capsule: the fillets meet the left (screen) edge, the rounded corners face right")
    func capsuleCorners() {
        let rect = CGRect(x: 0, y: 0, width: Theme.capsuleWidth, height: 200)
        let f = Theme.edgeFilletRadius
        let shape = CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: f, bodyHeight: 200 - f * 2)
        var left = shape
        left.side = .left
        let rightPath = shape.path(in: rect)
        let leftPath = left.path(in: rect)
        // The fillet: filled between its concave arc and the screen edge, above the body, on that side only.
        let tipY = f * 0.6
        #expect(rightPath.contains(CGPoint(x: rect.maxX - 0.5, y: tipY)))
        #expect(leftPath.contains(CGPoint(x: rect.minX + 0.5, y: tipY)))
        #expect(!leftPath.contains(CGPoint(x: rect.maxX - 0.5, y: tipY)))
        // The rounded corner: cut away at the inner edge's top corner of the body.
        #expect(!rightPath.contains(CGPoint(x: rect.minX + 0.5, y: f + 0.5)))
        #expect(!leftPath.contains(CGPoint(x: rect.maxX - 0.5, y: f + 0.5)))
        #expect(leftPath.contains(CGPoint(x: rect.minX + 0.5, y: f + 0.5)), "square at the screen edge")
        // The same outline, mirrored, everywhere.
        for x in stride(from: CGFloat(0.25), to: rect.width, by: 2) {
            for y in stride(from: CGFloat(0.25), to: rect.height, by: 3) {
                #expect(leftPath.contains(CGPoint(x: x, y: y)) == rightPath.contains(CGPoint(x: rect.width - x, y: y)))
            }
        }
        // A flush corner squares off on the left side's inner (right) corner.
        var flush = left
        flush.topCornerRadius = 0
        #expect(flush.path(in: rect).contains(CGPoint(x: rect.maxX - 0.5, y: f + 0.5)))
    }

    // MARK: Goo

    /// The open goo state of a slot's bulge at rest.
    private func openState(slot: Int, rows: Int, actions: Int) -> GooState {
        let span = PanelModel.bulgeSpan(slot: slot, rows: rows, actions: actions)
        return GooState(
            bodyHeight: Theme.capsuleBodyHeight(rows: rows, actions: actions), bodyExtraWidth: 0,
            bulgeWidth: Theme.bulgeWidth, bulgeCenterY: span.centerY, bulgeHeight: span.height,
            bulgeTopFlush: span.flushTop, bulgeBottomFlush: span.flushBottom
        )
    }

    @Test("Path renderer, left: the bulge grows rightward out of the capsule, the right outline mirrored")
    func pathRendererMirrors() {
        let rows = 3, actions = 0
        let height = Theme.capsuleHeight(rows: rows, actions: actions)
        let rect = CGRect(x: 0, y: 0, width: Theme.contentWidth, height: height)
        for slot in [0, 1, 2] {
            let state = openState(slot: slot, rows: rows, actions: actions)
            let right = GooPathShape(state: state, capsuleHeight: height).path(in: rect)
            let left = GooPathShape(state: state, capsuleHeight: height, side: .left).path(in: rect)
            let span = GooLayout.bulgeSpan(state: state, height: height)
            let reach = Theme.bulgeWidth - Theme.bulgeOverlap
            // The blob's middle: right of the capsule on the left side, left of it on the right side.
            #expect(left.contains(CGPoint(x: Theme.capsuleWidth + reach / 2, y: span.centerY)))
            #expect(right.contains(CGPoint(x: Theme.contentWidth - Theme.capsuleWidth - reach / 2, y: span.centerY)))
            #expect(!left.contains(CGPoint(x: Theme.capsuleWidth + reach + 2, y: span.centerY)), "no further than the reach")
            for x in stride(from: CGFloat(0.25), to: rect.width, by: 4) {
                for y in stride(from: CGFloat(0.25), to: height, by: 4) {
                    #expect(left.contains(CGPoint(x: x, y: y)) == right.contains(CGPoint(x: rect.width - x, y: y)))
                }
            }
        }
    }

    @Test("Threshold renderer, left: the canonical screen edge lands at the content's left edge, the bleed beyond it")
    func canvasRendererMirrors() {
        let bleed = Theme.gooBleed
        let right = GooCanvasView.drawingTransform(side: .right, bleed: bleed)
        let left = GooCanvasView.drawingTransform(side: .left, bleed: bleed)
        #expect(right == .identity)
        #expect(GooCanvasView.bleedOffset(side: .right, bleed: bleed) == bleed / 2)
        #expect(GooCanvasView.bleedOffset(side: .left, bleed: bleed) == -bleed / 2)
        // Canvas x to content x: the canvas is centred on the content, then moved by the bleed offset.
        func contentX(_ canonical: CGFloat, _ side: PanelSide, _ transform: CGAffineTransform) -> CGFloat {
            let canvasX = CGPoint(x: canonical, y: 0).applying(transform).x
            return canvasX - bleed / 2 + GooCanvasView.bleedOffset(side: side, bleed: bleed)
        }
        #expect(abs(contentX(Theme.contentWidth, .right, right) - Theme.contentWidth) < tolerance)
        #expect(abs(contentX(Theme.contentWidth, .left, left)) < tolerance, "the screen edge at content x 0")
        #expect(abs(contentX(Theme.contentWidth + bleed, .left, left) + bleed) < tolerance, "the bleed past the edge")
        #expect(abs(contentX(GooLayout.capsuleLeft, .left, left) - Theme.capsuleWidth) < tolerance, "the capsule's inner edge")
    }

    @Test("The bulge span and the text placement are vertical rules, the same on both sides")
    func bulgeSpanIsSideIndependent() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        var idle = try TestSupport.fixtureRecord("idle-desktop")
        var busy = try TestSupport.fixtureRecord("busy-desktop")
        idle.pid = TestSupport.livePid
        busy.pid = TestSupport.otherLivePid
        store.reconcile(RegistryScanResult(records: [idle, busy], presentPids: [idle.pid, busy.pid]))
        let right = PanelModel(store: store, newSessionButton: true)
        let left = PanelModel(store: store, newSessionButton: true, side: .left)
        for slot in [PanelModel.newSessionSlot, 0, 1] {
            #expect(left.bulgeSpan(slot: slot) == right.bulgeSpan(slot: slot))
            #expect(left.bulgeTextPlacement(slot: slot) == right.bulgeTextPlacement(slot: slot))
        }
    }

    // MARK: Edge cue

    @Test("Left edge cue: on the capsule's inner edge, which is its right edge, the right side's mirrored")
    func edgeCueSide() {
        let right = AttentionEdgeLayout.rect(slot: 1, rows: 3, actions: 1, newSession: true)
        let left = AttentionEdgeLayout.rect(slot: 1, rows: 3, actions: 1, newSession: true, side: .left)
        #expect(abs(right.minX - (GooLayout.capsuleLeft + Theme.attentionEdgeInset)) < tolerance)
        #expect(abs(left.maxX - (Theme.capsuleWidth - Theme.attentionEdgeInset)) < tolerance)
        #expect(left == PanelSide.left.mirror(right, in: Theme.contentWidth))
        #expect(left.midY == right.midY && left.size == right.size)
    }

    // MARK: Throw

    @Test("Left press axis: rightward first is a throw, leftward (toward the edge) stays a click")
    func pressAxis() {
        #expect(PressAxis.decide(dx: 15, dy: 0, canThrow: true, side: .left) == .throwFace)
        #expect(PressAxis.decide(dx: -15, dy: 0, canThrow: true, side: .left) == .click)
        #expect(PressAxis.decide(dx: 15, dy: 0, canThrow: true, side: .right) == .click)
        #expect(PressAxis.decide(dx: 15, dy: 0, canThrow: false, side: .left) == .click)
        #expect(PressAxis.decide(dx: 20, dy: 12, canThrow: true, side: .left) == .throwFace, "the larger travel wins")
        #expect(PressAxis.decide(dx: 12, dy: 20, canThrow: true, side: .left) == .dragPanel)
    }

    @Test("Left throw: out to the right by distance or speed, flying on rightward; leftward never throws")
    func throwDirection() {
        let travel = Theme.capsuleWidth / 2 + Theme.throwDistance + 10
        var out = FaceThrow(key: 1, start: CGPoint(x: 30, y: 500), at: 0, side: .left)
        out.moved(to: CGPoint(x: 30 + travel, y: 500), at: 0.5)
        out.moved(to: CGPoint(x: 30 + travel, y: 500), at: 1.0)
        let release = out.release(reduceMotion: false)
        #expect(release.removes)
        #expect(abs(release.pose.dx - (travel + Theme.throwFlyDistance)) < 0.001, "resting: it flies on to the right")

        var flick = FaceThrow(key: 1, start: CGPoint(x: 30, y: 500), at: 0, side: .left)
        flick.moved(to: CGPoint(x: 45, y: 500), at: 0.02)
        flick.moved(to: CGPoint(x: 60, y: 490), at: 0.04)
        let flung = flick.release(reduceMotion: false)
        #expect(flung.removes, "750 pt/s to the right")
        #expect(flung.pose.dx > 30 + Theme.throwFlyDistance * 0.9)
        #expect(flung.pose.dy > 3, "moving down a little, it flies a little down")
        #expect(flick.heldPose(reduceMotion: false).angle < 0, "moving right tilts the top to the right")

        var back = FaceThrow(key: 1, start: CGPoint(x: 60, y: 500), at: 0, side: .left)
        back.moved(to: CGPoint(x: 0, y: 500), at: 0.02)
        back.moved(to: CGPoint(x: -60, y: 500), at: 0.04)
        #expect(!back.release(reduceMotion: false).removes, "fast toward the edge never throws")
        // The right side unchanged: the same rightward flick does not throw there.
        var right = FaceThrow(key: 1, start: CGPoint(x: 30, y: 500), at: 0)
        right.moved(to: CGPoint(x: 45, y: 500), at: 0.02)
        right.moved(to: CGPoint(x: 60, y: 490), at: 0.04)
        #expect(!right.release(reduceMotion: false).removes)
    }

    // MARK: Pointer and magnification

    @Test("Left pointer: measured from the left edge; the capsule, the bulge, the throw target, the magnify lean")
    func pointerOnTheLeft() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        var idle = try TestSupport.fixtureRecord("idle-desktop")
        var busy = try TestSupport.fixtureRecord("busy-desktop")
        idle.pid = TestSupport.livePid
        busy.pid = TestSupport.otherLivePid
        store.reconcile(RegistryScanResult(records: [idle, busy], presentPids: [idle.pid, busy.pid]))
        let hidden = HiddenSessions(defaults: UserDefaults(suiteName: "PanelSideTests-\(UUID().uuidString)")!)
        let model = PanelModel(store: store, hiddenSessions: hidden, side: .left)
        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        let y = PanelModel.rowCenterY(index: 1)

        #expect(model.capsuleCenterX(inViewWidth: size.width) == Theme.capsuleWidth / 2)
        model.pointerMoved(to: CGPoint(x: Theme.capsuleWidth / 2, y: y), in: size)
        #expect(model.hoveredRowIndex == 1 && model.isExpanded)
        model.pointerMoved(to: CGPoint(x: Theme.capsuleWidth + 50, y: y), in: size)
        #expect(model.hoveredRowIndex == 1, "on the open bulge, right of the capsule, the hover stays")
        model.pointerMoved(to: CGPoint(x: size.width - 5, y: y - Theme.rowPitch), in: size)
        #expect(!model.isExpanded, "far from the edge, off the bulge, the hover ends")

        #expect(model.throwTarget(atViewPoint: CGPoint(x: Theme.capsuleWidth / 2, y: y), in: size) == model.rows[1].key)
        #expect(model.throwTarget(atViewPoint: CGPoint(x: Theme.capsuleWidth + 20, y: y), in: size) == nil, "the bulge")

        // Magnification leans toward the real pointer: toward the screen edge is leftward here.
        model.pointerMoved(to: CGPoint(x: 4, y: y), in: size)
        let lean = model.magnify(slot: 1)
        #expect(lean.dx < 0 && lean.scale > 1)
        #expect(model.pointer?.x == 4, "the pointer in the capsule's own coordinates, from its left edge on screen")
    }

    // MARK: Faces

    @Test("Left faces are mirrored about their centre: the genie's tip and the gaze point at the screen")
    func faceMirror() {
        #expect(CATransform3DIsIdentity(PanelSide.right.faceTransform))
        let flip = CATransform3DGetAffineTransform(PanelSide.left.faceTransform)
        #expect(flip.a == -1 && flip.d == 1 && flip.tx == 0)
        // The stretched blob reaches farther left than right of its centre (y up, centred at 0.5).
        let size: CGFloat = 1
        let box = BlobGenie.stretched(BlobShape.round.profile).path(size: size).boundingBoxOfPath
        let centre = size / 2
        #expect(centre - box.minX > box.maxX - centre)
        // Mirrored about the centre (the sublayer transform flips about the anchor), it reaches right.
        let mirrored = box.offsetBy(dx: -centre, dy: 0).applying(flip).offsetBy(dx: centre, dy: 0)
        #expect(mirrored.maxX - centre > centre - mirrored.minX)
        #expect(BlobLayerTree.geniePose(hovered: true, size: 44).shift < 0, "shifted toward the bulge, before the mirror")
    }

    @Test("FaceView carries the side into the configuration the layer trees read")
    func faceConfigurationCarriesTheSide() {
        var config = FaceConfiguration(identity: FaceIdentity(seed: "s"), mode: .status(.working), size: 44, filter: .none)
        #expect(config.side == .right)
        config.side = .left
        #expect(config != FaceConfiguration(identity: FaceIdentity(seed: "s"), mode: .status(.working), size: 44, filter: .none))
    }

    // MARK: Settings

    @Test("The panel side round-trips: stored, read back, set by key, overridden by --side without being written")
    func settingsRoundTrip() {
        let name = "PanelSideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.panelSide == .right)
        settings.panelSide = .left
        #expect(defaults.string(forKey: AppSettings.Key.panelSide) == "left")
        #expect(AppSettings(defaults: defaults).panelSide == .left)

        #expect(settings.setValue("right", forKey: "panelSide"))
        #expect(settings.panelSide == .right && defaults.string(forKey: "panelSide") == "right")
        #expect(!settings.setValue("top", forKey: "panelSide"), "an unknown side is refused")
        #expect(settings.panelSide == .right)

        let arguments = LaunchArguments(["Wallflower", "--side", "left"])
        #expect(arguments.panelSide == .left)
        let overridden = AppSettings(defaults: defaults, overrides: arguments.settingsOverrides)
        #expect(overridden.panelSide == .left)
        #expect(defaults.string(forKey: "panelSide") == "right", "a launch argument is never written back")
        #expect(LaunchArguments(["Wallflower", "--side", "middle"]).panelSide == nil)

        settings.panelSide = .left
        settings.restoreAppearanceDefaults()
        #expect(settings.panelSide == .left, "not an appearance value: Restore defaults leaves it")
        #expect(PanelSide.settingsChoices == [.left, .right])
        #expect(PanelSide.left.title == "Left" && PanelSide.right.title == "Right")
    }
}
