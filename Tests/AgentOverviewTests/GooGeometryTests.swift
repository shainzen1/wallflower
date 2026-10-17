import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import AgentOverview

/// The bulge stays inside the capsule body (both renderers and the texts take the same rule): kept
/// off the body's ends at the middle slots, flush with them at the first and last slot. The capsule's
/// edge fillets meet the screen edge as clean points in the threshold renderer (a crisp pass over a
/// blurred core that runs past the edge).
@Suite("Goo geometry: the bulge stays in the body, flush at the ends; the tips meet the edge")
@MainActor
struct GooGeometryTests {
    private let margin = Theme.bulgeEdgeMargin
    private let bodyTop = Theme.edgeFilletRadius
    private let tolerance: CGFloat = 0.000_001

    private func bodyBottom(rows: Int, actions: Int, newSession: Bool) -> CGFloat {
        bodyTop + Theme.capsuleBodyHeight(rows: rows, actions: actions, newSession: newSession)
    }

    /// The open goo state of a slot's bulge at rest, as `CapsuleView` builds it.
    private func openState(slot: Int, rows: Int, actions: Int, newSession: Bool) -> GooState {
        let span = PanelModel.bulgeSpan(slot: slot, rows: rows, actions: actions, newSession: newSession)
        return GooState(
            bodyHeight: Theme.capsuleBodyHeight(rows: rows, actions: actions, newSession: newSession), bodyExtraWidth: 0,
            bulgeWidth: Theme.bulgeWidth, bulgeCenterY: span.centerY, bulgeHeight: span.height,
            bulgeTopFlush: span.flushTop, bulgeBottomFlush: span.flushBottom
        )
    }

    // MARK: Bulge span: flush at the ends, the margin in the middle

    @Test("The new session button's bulge: its own shorter height, its top edge flush with the body's top")
    func topSlot() {
        for (rows, actions) in [(2, 2), (1, 0), (0, 2)] {
            let span = PanelModel.bulgeSpan(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
            let centre = PanelModel.slotCenterY(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
            #expect(span.height == Theme.newSessionPitch + Theme.bulgePadding * 2, "56 pt, as before")
            #expect(abs(span.minY - bodyTop) < tolerance, "\(span.minY)")
            #expect(span.flushTop == 1 && span.flushBottom == 0)
            #expect(span.centerY < centre, "moved up, onto the edge")
            #expect(abs(span.centerY - 38) < tolerance, "38 pt with today's constants (\(span.centerY))")
        }
    }

    @Test("The first slot without the button: a full row bulge (or the first action's), flush with the body's top")
    func firstRow() {
        let span = PanelModel.bulgeSpan(slot: 0, rows: 3, actions: 0)
        #expect(span.height == GooLayout.bulgeHeight)
        #expect(abs(span.minY - bodyTop) < tolerance)
        #expect(span.flushTop == 1 && span.flushBottom == 0)
        #expect(abs(span.centerY - (PanelModel.rowCenterY(index: 0) - 2)) < tolerance, "moved up by 2 pt")
        // No rows, only actions: the first action row is the first slot.
        let action = PanelModel.bulgeSpan(slot: 0, rows: 0, actions: 2)
        #expect(abs(action.minY - bodyTop) < tolerance && action.height == GooLayout.bulgeHeight)
        // With the button on, row 0 is a middle slot.
        #expect(PanelModel.bulgeSpan(slot: 0, rows: 3, actions: 0, newSession: true).flushTop == 0)
    }

    @Test("The last slot: the last action row, or the last session row without actions, flush with the body's bottom")
    func lastSlot() {
        for newSession in [false, true] {
            for (rows, actions) in [(2, 2), (3, 0), (0, 2)] {
                let slot = rows + actions - 1
                let span = PanelModel.bulgeSpan(slot: slot, rows: rows, actions: actions, newSession: newSession)
                let bottom = bodyBottom(rows: rows, actions: actions, newSession: newSession)
                #expect(span.height == GooLayout.bulgeHeight)
                #expect(abs(span.maxY - bottom) < tolerance, "\(span.maxY) vs \(bottom)")
                #expect(span.flushBottom == 1 && span.flushTop == (!newSession && slot == 0 ? 1 : 0))
                let centre = PanelModel.slotCenterY(slot: slot, rows: rows, actions: actions, newSession: newSession)
                #expect(span.centerY > centre, "moved down, onto the edge")
            }
        }
    }

    @Test("A middle row keeps its bulge centred on the slot, at the full height, the margin off both ends")
    func middleRow() {
        for newSession in [false, true] {
            let span = PanelModel.bulgeSpan(slot: 1, rows: 3, actions: 1, newSession: newSession)
            #expect(span.centerY == PanelModel.slotCenterY(slot: 1, rows: 3, actions: 1, newSession: newSession))
            #expect(span.height == GooLayout.bulgeHeight)
            #expect(span.flushTop == 0 && span.flushBottom == 0)
        }
        // The clamp still holds for a blob that would cross a non-flush end.
        let body: ClosedRange<CGFloat> = 10 ... 300
        let clamped = GooLayout.bulgeSpan(slotCenterY: 20, height: 64, body: body)
        #expect(abs(clamped.minY - (10 + margin)) < tolerance && clamped.flushTop == 0)
    }

    @Test("A slot alone is first and last: the blob spans the whole body, both edges flush")
    func singleSlot() {
        // One row alone: 68 pt of body, the blob grows from 64 pt to it.
        let row = PanelModel.bulgeSpan(slot: 0, rows: 1, actions: 0)
        #expect(abs(row.minY - bodyTop) < tolerance && abs(row.maxY - bodyBottom(rows: 1, actions: 0, newSession: false)) < tolerance)
        #expect(row.flushTop == 1 && row.flushBottom == 1)
        // The button alone: 60 pt of body.
        let button = PanelModel.bulgeSpan(slot: PanelModel.newSessionSlot, rows: 0, actions: 0, newSession: true)
        #expect(abs(button.minY - bodyTop) < tolerance && abs(button.maxY - bodyBottom(rows: 0, actions: 0, newSession: true)) < tolerance)
        #expect(button.height == Theme.capsuleBodyHeight(rows: 0, actions: 0, newSession: true))
        // A body shorter than the blob cuts it to the body; never negative.
        let short: ClosedRange<CGFloat> = 10 ... 50
        let cut = GooLayout.bulgeSpan(slotCenterY: 30, height: 64, body: short, flushTop: true, flushBottom: true)
        #expect(cut.minY == 10 && cut.maxY == 50)
        let tiny: ClosedRange<CGFloat> = 10 ... 20
        #expect(GooLayout.bulgeSpan(slotCenterY: 0, height: 64, body: tiny).height == 0, "never negative")
    }

    @Test("The renderers clamp into the live body too, and a flush edge stays on the springing body's edge")
    func renderersClampToLiveBody() {
        let height = Theme.capsuleHeight(rows: 3)
        // The body is still short (rows arriving): its top sits lower in the canvas than at rest.
        let live = Theme.capsuleBodyHeight(rows: 2)
        let liveTop = (height - live) / 2
        let state = GooState(
            bodyHeight: live, bodyExtraWidth: 0, bulgeWidth: Theme.bulgeWidth,
            bulgeCenterY: PanelModel.rowCenterY(index: 0), bulgeHeight: GooLayout.bulgeHeight
        )
        let rect = GooLayout.bulgeRect(state: state, height: height)
        #expect(abs(rect.minY - (liveTop + margin)) < tolerance)
        #expect(rect.height == GooLayout.bulgeHeight && rect.maxX == GooLayout.capsuleLeft + Theme.bulgeOverlap)

        // The first slot, flush: the blob's top follows the live top, shorter or taller than at rest.
        var flush = openState(slot: 0, rows: 3, actions: 0, newSession: false)
        for body in [Theme.capsuleBodyHeight(rows: 2), Theme.capsuleBodyHeight(rows: 4)] {
            flush.bodyHeight = body
            let top = GooLayout.bulgeRect(state: flush, height: height).minY
            #expect(abs(top - (height - body) / 2) < tolerance, "\(top)")
        }
    }

    @Test("A flush edge ramps in with the blob's reach: at the margin while closed, flush once open")
    func flushRampsWithReach() {
        let rows = 3
        let height = Theme.capsuleHeight(rows: rows)
        var state = openState(slot: 0, rows: rows, actions: 0, newSession: false)
        state.bulgeWidth = Theme.bulgeOverlap
        #expect(GooLayout.flushWeights(state: state).top == 0)
        #expect(abs(GooLayout.bulgeSpan(state: state, height: height).minY - (bodyTop + margin)) < tolerance)
        #expect(GooLayout.capsuleCornerRadii(state: state).top == Theme.capsuleCornerRadius)
        state.bulgeWidth = Theme.bulgeOverlap + Theme.bulgeFlushReach / 2
        #expect(abs(GooLayout.bulgeSpan(state: state, height: height).minY - (bodyTop + margin / 2)) < tolerance)
        #expect(abs(GooLayout.capsuleCornerRadii(state: state).top - Theme.capsuleCornerRadius / 2) < tolerance)
        state.bulgeWidth = Theme.bulgeWidth
        #expect(abs(GooLayout.bulgeSpan(state: state, height: height).minY - bodyTop) < tolerance)
        #expect(GooLayout.capsuleCornerRadii(state: state).top == 0)
        #expect(GooLayout.capsuleCornerRadii(state: state).bottom == Theme.capsuleCornerRadius)
        // `.all` mode: the bulge is closed, the whole body widens; nothing is flush, the corners stay round.
        let all = GooState(
            bodyHeight: state.bodyHeight, bodyExtraWidth: Theme.bulgeWidth, bulgeWidth: 0,
            bulgeCenterY: state.bulgeCenterY, bulgeHeight: state.bulgeHeight, bulgeTopFlush: 1, bulgeBottomFlush: 1
        )
        #expect(GooLayout.capsuleCornerRadii(state: all).top == Theme.capsuleCornerRadius)
        #expect(GooLayout.capsuleCornerRadii(state: all).bottom == Theme.capsuleCornerRadius)
        let wideRect = GooLayout.capsuleRect(state: all, height: height)
        let shape = GooPathShape(state: all, capsuleHeight: height).path(in: CGRect(x: 0, y: 0, width: Theme.contentWidth, height: height))
        let plain = CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: Theme.edgeFilletRadius, bodyHeight: all.bodyHeight)
            .path(in: wideRect)
        var mismatches = 0
        for x in stride(from: wideRect.minX + 0.25, to: wideRect.maxX, by: 2) {
            for y in stride(from: 0.25, to: height, by: 2) where shape.contains(CGPoint(x: x, y: y)) != plain.contains(CGPoint(x: x, y: y)) {
                mismatches += 1
            }
        }
        #expect(mismatches == 0)
    }

    @Test("Travel from the first slot to the second: the blob, the corner and the fillet change continuously, no pop")
    func travelIsContinuous() {
        let rows = 3, actions = 1
        let height = Theme.capsuleHeight(rows: rows, actions: actions, newSession: true)
        let first = openState(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
        let second = openState(slot: 0, rows: rows, actions: actions, newSession: true)
        let left = GooLayout.capsuleLeft
        var lastTop: CGFloat?
        var lastFillet: CGFloat?
        // The fillet's height: how far it reaches up from the blob's edge (at most the gap to the body's top).
        for step in 0 ... 100 {
            var state = first
            state += (second - first).scaled(by: Double(step) / 100)
            let span = GooLayout.bulgeSpan(state: state, height: height)
            let corner = GooLayout.capsuleCornerRadii(state: state).top
            let piece = GooPathShape.fillet(
                left: left, bodyTop: bodyTop, cornerRadius: corner, edgeY: span.minY, radius: Theme.bulgeFilletRadius
            )
            let fillet = piece.isEmpty ? 0 : piece.boundingRect.height
            if let lastTop { #expect(abs(span.minY - lastTop) < 1.5, "step \(step): \(lastTop) to \(span.minY)") }
            if let lastFillet { #expect(abs(fillet - lastFillet) < 1.5, "step \(step): fillet \(lastFillet) to \(fillet)") }
            #expect(span.minY >= bodyTop - tolerance)
            lastTop = span.minY
            lastFillet = fillet
            if step == 0 { #expect(abs(span.minY - bodyTop) < tolerance && fillet == 0 && corner == 0) }
            if step == 1 { #expect(fillet < 1, "the fillet grows from nothing (\(fillet))") }
        }
    }

    @Test("The texts follow the blob in .row mode and stay on the slot in .all mode; the hover region is the blob")
    func textsAndHoverFollowTheBlob() throws {
        func model(_ mode: Theme.ExpandMode) throws -> (SessionStore, PanelModel) {
            let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
            var record = try TestSupport.fixtureRecord("idle-desktop")
            record.pid = TestSupport.livePid
            store.reconcile(RegistryScanResult(records: [record], presentPids: [record.pid]))
            return (store, PanelModel(store: store, expandMode: mode, newSessionButton: true))
        }
        let (rowStore, row) = try model(.row)
        defer { rowStore.stop() }
        let slot = PanelModel.newSessionSlot
        let span = row.bulgeSpan(slot: slot)
        let placement = row.bulgeTextPlacement(slot: slot)
        #expect(abs(placement.offset - (span.centerY - row.slotCenterY(slot: slot))) < tolerance && placement.offset < 0)
        #expect(placement.height == span.height)
        #expect(row.bulgeTextPlacement(slot: 0).offset > 0, "the only row is the last slot: its texts move down with the blob")

        // Hover region: the flush blob reaches the body's top; above it the hover ends.
        row.hover(rowIndex: slot)
        let dx = Theme.capsuleWidth + 100
        #expect(row.hoverRegionContains(distanceFromEdge: dx, y: span.minY + 0.5) == .bulge)
        #expect(row.hoverRegionContains(distanceFromEdge: dx, y: span.maxY - 0.5) == .bulge)
        #expect(row.hoverRegionContains(distanceFromEdge: dx, y: span.minY - 0.5) == .outside)

        let (allStore, all) = try model(.all)
        defer { allStore.stop() }
        let wide = all.bulgeTextPlacement(slot: slot)
        #expect(wide.offset == 0 && wide.height == Theme.newSessionPitch + Theme.bulgePadding * 2)
    }

    // MARK: Path renderer

    /// The y of the outline's edge in column `x` between `from` and `to` (empty at `from`, filled at
    /// `to`), by bisection.
    private func edge(of path: Path, x: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        var (empty, filled) = (from, to)
        for _ in 0 ..< 40 {
            let mid = (empty + filled) / 2
            if path.contains(CGPoint(x: x, y: mid)) { filled = mid } else { empty = mid }
        }
        return (empty + filled) / 2
    }

    @Test("Path renderer: a flush first or last slot is one straight edge from the blob's corner to the screen-edge fillet")
    func pathRendererFlushEdges() {
        let rows = 2, actions = 1
        let height = Theme.capsuleHeight(rows: rows, actions: actions, newSession: true)
        let rect = CGRect(x: 0, y: 0, width: Theme.contentWidth, height: height)
        let left = GooLayout.capsuleLeft
        let reach = Theme.bulgeWidth - Theme.bulgeOverlap
        // A continuous corner runs about 1.53 radii along the edge before the edge is straight.
        let straightFrom = left - reach + Theme.bulgeCornerRadius * 1.6
        let straightTo = Theme.contentWidth - Theme.edgeFilletRadius - 0.5
        let bottom = bodyBottom(rows: rows, actions: actions, newSession: true)

        let top = openState(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
        let topPath = GooPathShape(state: top, capsuleHeight: height).path(in: rect)
        let last = openState(slot: rows + actions - 1, rows: rows, actions: actions, newSession: true)
        let bottomPath = GooPathShape(state: last, capsuleHeight: height).path(in: rect)
        for x in stride(from: straightFrom, through: straightTo, by: 0.5) {
            let y = edge(of: topPath, x: x, from: bodyTop - 6, to: bodyTop + 6)
            #expect(abs(y - bodyTop) < 0.001, "top edge at x \(x): \(y)")
            let yb = edge(of: bottomPath, x: x, from: bottom + 6, to: bottom - 6)
            #expect(abs(yb - bottom) < 0.001, "bottom edge at x \(x): \(yb)")
        }
        // No fillet on the flush side: the piece is empty, the edge collinear.
        let fillet = GooPathShape.fillet(left: left, bodyTop: bodyTop, cornerRadius: 0, edgeY: bodyTop, radius: Theme.bulgeFilletRadius)
        #expect(fillet.isEmpty)
        // The far side of the button's blob keeps its fillet against the capsule's straight side.
        let span = GooLayout.bulgeSpan(state: top, height: height)
        #expect(topPath.contains(CGPoint(x: left - 0.5, y: span.maxY + 0.5)), "filled in the fillet's angle")
        #expect(!topPath.contains(CGPoint(x: left - Theme.bulgeFilletRadius + 0.5, y: span.maxY + Theme.bulgeFilletRadius - 0.5)))
    }

    @Test("Path renderer: a middle slot keeps its fillets; a fillet against a corner shrinks to nothing as the edge rises to the body's top")
    func pathRendererFillets() {
        let rows = 3, actions = 1
        let height = Theme.capsuleHeight(rows: rows, actions: actions)
        let state = openState(slot: 1, rows: rows, actions: actions, newSession: false)
        let path = GooPathShape(state: state, capsuleHeight: height).path(in: CGRect(x: 0, y: 0, width: Theme.contentWidth, height: height))
        let span = GooLayout.bulgeSpan(state: state, height: height)
        let left = GooLayout.capsuleLeft
        #expect(path.contains(CGPoint(x: left - 0.5, y: span.minY - 0.5)) && path.contains(CGPoint(x: left - 0.5, y: span.maxY + 0.5)))
        #expect(!path.contains(CGPoint(x: left - 9.5, y: span.minY - 9.5)))
        // Straight side: the classic square-minus-disc piece.
        let straight = GooPathShape.fillet(left: left, bodyTop: 0, cornerRadius: 16, edgeY: 100, radius: 10).boundingRect
        #expect(abs(straight.minX - (left - 10)) < 0.01 && abs(straight.maxX - left) < 0.01 && abs(straight.minY - 90) < 0.01)
        // Against the rounded corner: concave, inside the corner's angle.
        let round = GooPathShape.fillet(left: left, bodyTop: bodyTop, cornerRadius: 16, edgeY: bodyTop + margin, radius: 10)
        #expect(!round.isEmpty && round.boundingRect.minY >= bodyTop - 0.000_1 && round.boundingRect.maxX <= left + 16)
        // Against a square corner, shrinking with the gap to the body's top.
        var widths: [CGFloat] = []
        for gap in [4.0, 1.0, 0.25, 0.01] as [CGFloat] {
            let piece = GooPathShape.fillet(left: left, bodyTop: bodyTop, cornerRadius: 0, edgeY: bodyTop + gap, radius: 10)
            #expect(piece.boundingRect.minY >= bodyTop - 0.000_1 && piece.boundingRect.maxX <= left + 0.000_1)
            widths.append(piece.boundingRect.width)
        }
        #expect(widths == widths.sorted(by: >) && widths.last! < 0.6, "\(widths)")
    }

    // MARK: Threshold renderer at the flush junction

    /// The `.blurThreshold` renderer's result, simulated: the blurred layer (capsule core and blob)
    /// rasterised (anti-aliased) in cells 1 pt wide and 0.5 pt tall, blurred with a Gaussian of
    /// `sigma`, cut at `Theme.gooThreshold`, and united with the crisp tips. Returns, per column (cell
    /// centres from `x0` to `x1`), the centre of the first filled cell scanning from `y0` toward `y1`.
    /// Nonisolated, so the tests run it off the main actor (other suites time main-actor work).
    nonisolated private static func thresholdEdge(
        state: GooState, height: CGFloat, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, sigma: CGFloat
    ) -> [Column] {
        let (cellX, cellY): (CGFloat, CGFloat) = (1, 0.5)
        let core = GooLayout.capsuleCore(state: state, height: height, bleed: Theme.gooBleed)
        let blob = GooLayout.bulgeBlob(state: state, height: height)
        let tips = GooLayout.capsuleTips(state: state, height: height, overhang: Theme.gooBleed)
        let pad = sigma * 4
        // Wide enough that everything within the kernel of the scanned cells is in the grid (the
        // core's bleed past the screen edge included); farther out nothing changes the result.
        let gx0 = x0 - pad, gx1 = max(x1, Theme.contentWidth + Theme.gooBleed) + pad
        let gy0 = min(y0, y1) - pad, gy1 = max(y0, y1) + pad
        let w = Int(((gx1 - gx0) / cellX).rounded(.up)), h = Int(((gy1 - gy0) / cellY).rounded(.up))
        func point(_ i: Int, _ j: Int) -> CGPoint { CGPoint(x: gx0 + (CGFloat(i) + 0.5) * cellX, y: gy0 + (CGFloat(j) + 0.5) * cellY) }
        // Memory row j is the cell row from gy0 + j * cellY down.
        let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1 / cellX, y: -1 / cellY)
        context.translateBy(x: -gx0, y: -gy0)
        context.setFillColor(gray: 1, alpha: 1)
        for path in [core, blob] {
            context.addPath(path.cgPath)
            context.fillPath()
        }
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: w * h)
        var image = (0 ..< w * h).map { Double(pixels[$0]) / 255 }
        func kernel(_ cell: CGFloat) -> [Double] {
            let radius = Int((sigma * 3 / cell).rounded(.up))
            let s = Double(sigma / cell)
            let raw = (-radius ... radius).map { exp(-Double($0 * $0) / (2 * s * s)) }
            let sum = raw.reduce(0, +)
            return raw.map { $0 / sum }
        }
        let kx = kernel(cellX), ky = kernel(cellY)
        let rx = kx.count / 2, ry = ky.count / 2
        var pass = [Double](repeating: 0, count: w * h)
        for j in 0 ..< h { for i in 0 ..< w {
            var v = 0.0
            for k in max(-rx, -i) ... min(rx, w - 1 - i) { v += image[j * w + i + k] * kx[k + rx] }
            pass[j * w + i] = v
        } }
        for j in 0 ..< h { for i in 0 ..< w {
            var v = 0.0
            for k in max(-ry, -j) ... min(ry, h - 1 - j) { v += pass[(j + k) * w + i] * ky[k + ry] }
            image[j * w + i] = v
        } }
        var result: [Column] = []
        let order = y1 > y0 ? Array(0 ..< h) : Array((0 ..< h).reversed())
        for i in 0 ..< w {
            let x = point(i, 0).x
            guard x >= x0, x <= x1 else { continue }
            var found: CGFloat?
            for j in order {
                let p = point(i, j)
                guard y1 > y0 ? p.y >= y0 : p.y <= y0 else { continue }
                if image[j * w + i] >= Theme.gooThreshold || tips.contains(p) { found = p.y; break }
            }
            result.append(Column(x: x, y: found))
        }
        return result
    }

    /// One column of `thresholdEdge`: its x and the first filled y (nil: none).
    struct Column: Sendable, CustomStringConvertible {
        var x: CGFloat
        var y: CGFloat?
        var description: String { "\(x): \(y.map { "\($0)" } ?? "none")" }
    }

    /// `thresholdEdge` off the main actor.
    private func thresholdEdge(
        state: GooState, height: CGFloat, x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat, sigma: CGFloat
    ) async -> [Column] {
        await Task.detached {
            Self.thresholdEdge(state: state, height: height, x0: x0, x1: x1, y0: y0, y1: y1, sigma: sigma)
        }.value
    }

    @Test("Threshold renderer: the flush junction thresholds to the straight body edge, no dip, at the top and the bottom")
    func thresholdRendererFlushJunction() async {
        let rows = 2, actions = 1
        let height = Theme.capsuleHeight(rows: rows, actions: actions, newSession: true)
        let left = GooLayout.capsuleLeft
        let bottom = bodyBottom(rows: rows, actions: actions, newSession: true)
        // From well right of the blob's rounded corner (the blur rounds that one further) to the
        // screen-edge fillet, across the junction at the capsule's left side.
        let x0 = left - 60, x1 = Theme.contentWidth - Theme.edgeFilletRadius - 1
        let top = openState(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
        for column in await thresholdEdge(state: top, height: height, x0: x0, x1: x1, y0: bodyTop - 20, y1: bodyTop + 20, sigma: Theme.gooBlur) {
            #expect(column.y.map { abs($0 - (bodyTop + 0.25)) < 0.3 } == true, "top at x \(column.x): \(String(describing: column.y))")
        }
        let last = openState(slot: rows + actions - 1, rows: rows, actions: actions, newSession: true)
        for column in await thresholdEdge(state: last, height: height, x0: x0, x1: x1, y0: bottom + 20, y1: bottom - 20, sigma: Theme.gooBlur) {
            #expect(column.y.map { abs($0 - (bottom - 0.25)) < 0.3 } == true, "bottom at x \(column.x): \(String(describing: column.y))")
        }
        // And past the fillet the crisp tips carry the outline to the screen edge, above the body's top.
        let tips = await thresholdEdge(state: top, height: height, x0: Theme.contentWidth - 2, x1: Theme.contentWidth - 1, y0: -5, y1: bodyTop + 5, sigma: Theme.gooBlur)
        #expect(!tips.isEmpty && tips.allSatisfy { ($0.y ?? .infinity) < bodyTop - 2 }, "\(tips)")
    }

    @Test("Threshold renderer, before the flush: the margin left a step the blur turned into a dip (the model catches it)")
    func thresholdRendererMarginDips() async {
        // The same simulation on a middle-style blob 6 pt below the body's top at the first slot.
        let rows = 2, actions = 1
        let height = Theme.capsuleHeight(rows: rows, actions: actions, newSession: true)
        var state = openState(slot: PanelModel.newSessionSlot, rows: rows, actions: actions, newSession: true)
        state.bulgeTopFlush = 0
        state.bulgeCenterY += margin
        let columns = await thresholdEdge(
            state: state, height: height, x0: GooLayout.capsuleLeft - 60, x1: GooLayout.capsuleLeft + 20,
            y0: bodyTop - 20, y1: bodyTop + 20, sigma: Theme.gooBlur
        )
        #expect(columns.contains { ($0.y ?? 0) > bodyTop + 3 }, "the old step shows in the simulation")
    }

    // MARK: Capsule tips (threshold renderer)

    @Test("Threshold renderer: the blurred core runs past the screen edge between the body's ends; the crisp tips complete the outline")
    func capsuleCoreAndTips() {
        let rows = 3
        let height = Theme.capsuleHeight(rows: rows)
        let state = GooState(bodyHeight: Theme.capsuleBodyHeight(rows: rows), bodyExtraWidth: 0, bulgeWidth: 0, bulgeCenterY: 0)
        let bleed = Theme.gooBleed
        let edge = Theme.contentWidth
        let f = Theme.edgeFilletRadius
        let core = GooLayout.capsuleCore(state: state, height: height, bleed: bleed)
        let tips = GooLayout.capsuleTips(state: state, height: height, overhang: bleed)
        let outline = CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: f, bodyHeight: state.bodyHeight)
            .path(in: GooLayout.capsuleRect(state: state, height: height))

        // Past the edge the core is the body only: solid between the body's top and bottom, nothing beyond.
        #expect(core.contains(CGPoint(x: edge + bleed / 2, y: height / 2)))
        #expect(core.contains(CGPoint(x: edge + bleed - 0.5, y: f + 0.5)))
        #expect(!core.contains(CGPoint(x: edge + 1, y: f - 0.5)), "no bezel above the body")
        #expect(!core.contains(CGPoint(x: edge + 1, y: height - f + 0.5)), "nor below it")
        #expect(!core.contains(CGPoint(x: edge - 0.5, y: f - 2)), "the fillets are not in the blurred core")

        // The tips are the fillets: the thin end reaches the edge at the window's top and bottom.
        #expect(tips.contains(CGPoint(x: edge - 0.2, y: 3)))
        #expect(!tips.contains(CGPoint(x: edge - 1, y: 1)))
        #expect(tips.contains(CGPoint(x: edge - 0.2, y: height - 3)))
        #expect(!tips.contains(CGPoint(x: edge - f - Theme.gooTipOverlap - 0.5, y: f + 1)), "nothing left of the overlap")
        // Past the edge they continue as their mirror image (for the edge soften), never as a block.
        #expect(tips.contains(CGPoint(x: edge + 0.2, y: 3)) && !tips.contains(CGPoint(x: edge + 1, y: 1)))

        // Inside the window, core and tips together are exactly the capsule outline (up to the arcs'
        // flattening: points within 0.4 pt of the outline's edge are not compared).
        var mismatches = 0
        let probes = [CGPoint(x: -0.4, y: 0), CGPoint(x: 0.4, y: 0), CGPoint(x: 0, y: -0.4), CGPoint(x: 0, y: 0.4)]
        for x in stride(from: GooLayout.capsuleLeft + 0.13, to: edge, by: 0.5) {
            for y in stride(from: 0.17, to: height, by: 0.5) {
                let point = CGPoint(x: x, y: y)
                let inside = outline.contains(point)
                guard probes.allSatisfy({ outline.contains(CGPoint(x: x + $0.x, y: y + $0.y)) == inside }) else { continue }
                if (core.contains(point) || tips.contains(point)) != inside { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
    }
}
