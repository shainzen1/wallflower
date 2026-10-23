import SwiftUI

/// Geometry shared by both goo renderers and the bulge content, in content coordinates:
/// origin at the top-left of the panel content (`Theme.contentWidth` wide, capsule height
/// tall, y down), the capsule flush with the right edge. This is the canonical (right-edge)
/// geometry only: on the left side the renderers draw it mirrored across the content width
/// (`PanelSide.transform(in:)`), so nothing here knows the side. The vertical rules (the bulge span,
/// the flush ends) are the same on both sides.
enum GooLayout {
    /// Height of a row's bulge blob: the row plus padding above and below.
    static let bulgeHeight = bulgeHeight(pitch: Theme.rowPitch)

    /// Height of the bulge blob of a slot `pitch` tall: the slot plus `Theme.bulgePadding` above and
    /// below. The new session button's shorter slot gets a shorter blob.
    static func bulgeHeight(pitch: CGFloat) -> CGFloat {
        pitch + Theme.bulgePadding * 2
    }

    /// Where a bulge blob sits vertically: its centre and height, from the top of the capsule
    /// (fillet included), like the slot centres, and how flush its top and bottom edges are with the
    /// body's (1 at the first and the last slot, 0 elsewhere; in between while it springs).
    struct BulgeSpan: Equatable, Sendable {
        var centerY: CGFloat
        var height: CGFloat
        var flushTop: CGFloat = 0
        var flushBottom: CGFloat = 0
        var minY: CGFloat { centerY - height / 2 }
        var maxY: CGFloat { centerY + height / 2 }
    }

    /// The one rule for the bulge's vertical place: centred on its slot, but never closer than
    /// `Theme.bulgeEdgeMargin` to the body's top or bottom (`body`, between the fillets), so the blob
    /// never breaks the capsule's top or bottom edge or crowds its rounded corners. At the first slot
    /// (`flushTop`) the blob is not kept off the top edge but moved onto it: its top edge is the
    /// body's, one straight line, and the capsule's top-left corner is absorbed by it. The same at
    /// the bottom for the last slot (`flushBottom`); a slot that is both spans the whole body. The
    /// blob keeps its height and moves; one taller than the room is cut to the room and centred in it.
    /// The model applies it to the final layout (`PanelModel.bulgeSpan(slot:)`) for the goo, the
    /// bulge texts and the hover region; the renderers keep the result inside the live, springing
    /// body (`bulgeSpan(state:height:)`).
    static func bulgeSpan(
        slotCenterY: CGFloat, height: CGFloat, body: ClosedRange<CGFloat>, flushTop: Bool = false, flushBottom: Bool = false
    ) -> BulgeSpan {
        var top = slotCenterY - height / 2
        var bottom = slotCenterY + height / 2
        if flushTop {
            bottom += body.lowerBound - top
            top = body.lowerBound
        }
        if flushBottom {
            if !flushTop { top += body.upperBound - bottom }
            bottom = body.upperBound
        }
        return clamp(top: top, bottom: bottom, body: body, flushTop: flushTop ? 1 : 0, flushBottom: flushBottom ? 1 : 0)
    }

    /// Keeps a blob from `top` to `bottom` inside `body`: `Theme.bulgeEdgeMargin` off each end,
    /// scaled down by that end's flush weight (0 to 1), so a flush end may reach the body's edge and a
    /// half flush one half the margin. A blob taller than the room is cut to it and centred in it.
    static func clamp(top: CGFloat, bottom: CGFloat, body: ClosedRange<CGFloat>, flushTop: CGFloat, flushBottom: CGFloat) -> BulgeSpan {
        let flushTop = min(max(flushTop, 0), 1)
        let flushBottom = min(max(flushBottom, 0), 1)
        let low = body.lowerBound + Theme.bulgeEdgeMargin * (1 - flushTop)
        let high = body.upperBound - Theme.bulgeEdgeMargin * (1 - flushBottom)
        let room = max(high - low, 0)
        let height = max(bottom - top, 0)
        guard height < room else {
            return BulgeSpan(centerY: (low + high) / 2, height: room, flushTop: flushTop, flushBottom: flushBottom)
        }
        let centre = min(max((top + bottom) / 2, low + height / 2), high - height / 2)
        return BulgeSpan(centerY: centre, height: height, flushTop: flushTop, flushBottom: flushBottom)
    }

    /// The bulge span of a state in a canvas `height` tall (the final capsule height): the model's
    /// span (`state.bulgeCenterY`, `state.bulgeHeight`) kept inside the state's (possibly still
    /// springing) body. Its flush weights are `flushWeights(state:)`: while the blob opens or closes
    /// they ramp with its reach, so a flush edge only meets the body's edge once the blob is wide
    /// enough to carry the corner. A flush edge is anchored to the body's edge: while the body
    /// springs away from its final size, that edge moves with it.
    static func bulgeSpan(state: GooState, height: CGFloat) -> BulgeSpan {
        let body = bodySpan(height: height, bodyHeight: state.bodyHeight)
        let rest = bodySpan(height: height, bodyHeight: height - Theme.edgeFilletRadius * 2)
        let flush = flushWeights(state: state)
        let top = state.bulgeCenterY - state.bulgeHeight / 2 + flush.top * (body.lowerBound - rest.lowerBound)
        let bottom = state.bulgeCenterY + state.bulgeHeight / 2 + flush.bottom * (body.upperBound - rest.upperBound)
        return clamp(top: top, bottom: bottom, body: body, flushTop: flush.top, flushBottom: flush.bottom)
    }

    /// How flush the drawn blob's top and bottom edges are, 0 to 1: the state's flush values, times
    /// how far the blob reaches out of the capsule over `Theme.bulgeFlushReach`. A blob that is
    /// opening (or closing) at the first slot rises to the body's top edge as it grows, and the
    /// capsule's corner squares off under it; nothing is flush while the bulge is closed (the
    /// `.all` mode body, too, keeps its corners).
    static func flushWeights(state: GooState) -> (top: CGFloat, bottom: CGFloat) {
        let open = min(max((state.bulgeWidth - Theme.bulgeOverlap) / Theme.bulgeFlushReach, 0), 1)
        return (min(max(state.bulgeTopFlush, 0), 1) * open, min(max(state.bulgeBottomFlush, 0), 1) * open)
    }

    /// The capsule's top-left and bottom-left corner radii under a state: `Theme.capsuleCornerRadius`,
    /// shrinking to 0 (a square corner, inside the flush blob) as that side's flush weight reaches 1.
    static func capsuleCornerRadii(state: GooState) -> (top: CGFloat, bottom: CGFloat) {
        let flush = flushWeights(state: state)
        return (Theme.capsuleCornerRadius * (1 - flush.top), Theme.capsuleCornerRadius * (1 - flush.bottom))
    }

    /// The edge fillet radius drawn for a body `bodyHeight` tall: `Theme.edgeFilletRadius` once the
    /// body is `Theme.edgeFilletFullBody` tall, in proportion below that (half size on the lone new
    /// session button's 60 pt body). It follows the springing body, so the fillets grow and shrink with
    /// it. Only the drawing uses it: the window and the slots keep the full `Theme.edgeFilletRadius`
    /// above and below the body, and a smaller fillet leaves that room transparent at the screen edge.
    static func edgeFilletRadius(bodyHeight: CGFloat) -> CGFloat {
        Theme.edgeFilletRadius * min(max(bodyHeight / Theme.edgeFilletFullBody, 0), 1)
    }

    /// The capsule outline under a state: `CapsuleShape` with the corners `capsuleCornerRadii`
    /// and edge fillets of `filletRadius`.
    static func capsuleShape(state: GooState, filletRadius: CGFloat) -> CapsuleShape {
        let radii = capsuleCornerRadii(state: state)
        return CapsuleShape(
            cornerRadius: Theme.capsuleCornerRadius, filletRadius: filletRadius, bodyHeight: state.bodyHeight,
            topCornerRadius: radii.top, bottomCornerRadius: radii.bottom
        )
    }

    /// Left edge of the capsule at rest (without `.all` mode widening).
    static let capsuleLeft = Theme.contentWidth - Theme.capsuleWidth

    /// Rect the capsule shape is drawn in: right-aligned, widened to the left in `.all` mode.
    static func capsuleRect(state: GooState, height: CGFloat) -> CGRect {
        let extra = max(state.bodyExtraWidth, 0)
        return CGRect(x: capsuleLeft - extra, y: 0, width: Theme.capsuleWidth + extra, height: height)
    }

    /// `.blurThreshold` renderer, the part that goes through the blur: the capsule without its edge
    /// fillets, its body continued past the screen edge (the right edge of `capsuleRect`) as a solid
    /// block `bleed` wide, between the body's top and bottom only. Past the edge the body's top and
    /// bottom stay one straight line, so the threshold keeps them where the crisp outline has them.
    /// The fillets are not blurred: under a blur as wide as the fillet, the concave corner between the
    /// body and the edge fills in, the thresholded arc ends a few points short of the screen edge and
    /// the window clips it flat. They come from `capsuleTips` instead, drawn crisp on top.
    ///
    /// One outline, no path boolean: the fillet-less `CapsuleShape` drawn in the capsule rect widened by
    /// `bleed` past the screen edge is exactly the capsule plus the block (see `capsuleTips` for why the
    /// renderer avoids `Path.union` and friends).
    static func capsuleCore(state: GooState, height: CGFloat, bleed: CGFloat) -> Path {
        let rect = capsuleRect(state: state, height: height)
        let wide = CGRect(x: rect.minX, y: rect.minY, width: rect.width + max(bleed, 0), height: rect.height)
        return capsuleShape(state: state, filletRadius: 0).path(in: wide)
    }

    /// `.blurThreshold` renderer, the crisp pass: the capsule's two edge fillet regions (the sliver
    /// between each concave arc and the screen edge, as `CapsuleShape` draws it), each reaching
    /// `Theme.gooTipOverlap` past the fillet into the body (left and toward the middle), where the
    /// blurred core is solid or has the same straight edge, so the two passes meet without a seam. The
    /// tips meet the screen edge as clean points. Past the screen edge each piece continues `overhang`
    /// wide as its own mirror image, so the edge-soften blur on this pass sees the same shape on both
    /// sides of the edge: it neither lightens the edge column nor thickens the thin end of the tip.
    ///
    /// Built outline by outline, never with a path boolean. It used to be the capsule outline united
    /// with its own mirror image and cut to two rects with `Path.union` and `Path.intersection`. The two
    /// outlines share the whole screen-edge line, a coincident edge, and on macOS 26 (seen on 26.6.2;
    /// 27 is fine) the boolean result came back as the full cutting rects: each tip drew as a solid
    /// block `reach` wide and the fillet room tall, a hard-edged black strip on the screen edge that
    /// stood out above and below the capsule (most visibly on a short capsule).
    static func capsuleTips(state: GooState, height: CGFloat, overhang: CGFloat = 0) -> Path {
        let rect = capsuleRect(state: state, height: height)
        let f = max(min(edgeFilletRadius(bodyHeight: state.bodyHeight), rect.width / 2), 0)
        guard f > 0 else { return Path() }
        let body = bodySpan(height: height, bodyHeight: state.bodyHeight)
        let edge = rect.maxX
        let reach = f + Theme.gooTipOverlap
        // How far each piece reaches into the body: never past the body's middle, so the two pieces
        // stay apart on a short body.
        let overlap = max(min(Theme.gooTipOverlap, (body.upperBound - body.lowerBound) / 2), 0)
        // The top piece (y down): along the body's top edge to the fillet, up the concave arc to the
        // screen edge, then (past the edge) down the mirrored arc and along the mirrored top edge, and
        // back along the bottom of the overlap band.
        let top = body.lowerBound
        var piece = Path()
        piece.move(to: CGPoint(x: edge - reach, y: top))
        piece.addLine(to: CGPoint(x: edge - f, y: top))
        piece.addRelativeArc(center: CGPoint(x: edge - f, y: top - f), radius: f, startAngle: .degrees(90), delta: .degrees(-90))
        let far: CGFloat
        if overhang > 0 {
            piece.addRelativeArc(center: CGPoint(x: edge + f, y: top - f), radius: f, startAngle: .degrees(180), delta: .degrees(-90))
            far = edge + max(overhang + 1, f)
            piece.addLine(to: CGPoint(x: far, y: top))
        } else {
            far = edge
        }
        piece.addLine(to: CGPoint(x: far, y: top + overlap))
        piece.addLine(to: CGPoint(x: edge - reach, y: top + overlap))
        piece.closeSubpath()
        // The bottom piece is the top one flipped about the body's middle.
        let flip = CGAffineTransform(translationX: 0, y: body.lowerBound + body.upperBound).scaledBy(x: 1, y: -1)
        var tips = piece
        tips.addPath(piece.applying(flip))
        return tips
    }

    /// Top and bottom of the capsule body (between the fillets) while it is `bodyHeight` tall in a
    /// canvas `height` tall: `CapsuleShape` centres the body vertically.
    static func bodySpan(height: CGFloat, bodyHeight: CGFloat) -> ClosedRange<CGFloat> {
        let body = max(bodyHeight, 0)
        return (height - body) / 2 ... (height + body) / 2
    }

    /// The bulge blob in a canvas `height` tall: a rounded rect whose right edge reaches
    /// `Theme.bulgeOverlap` into the capsule, placed by `bulgeSpan(state:height:)`.
    static func bulgeRect(state: GooState, height: CGFloat) -> CGRect {
        let width = max(state.bulgeWidth, 0)
        let span = bulgeSpan(state: state, height: height)
        return CGRect(x: capsuleLeft + Theme.bulgeOverlap - width, y: span.minY, width: width, height: span.height)
    }

    /// `.blurThreshold` renderer: the bulge blob's path, its corners rounded by `bulgeCornerRadius`,
    /// except the right one on a flush side, which squares off with the flush weight. That corner
    /// lies inside the capsule, under the capsule's own (absorbed) corner; rounded, the two would
    /// leave a notch at the body's top edge that the blur turns into a dip.
    static func bulgeBlob(state: GooState, height: CGFloat) -> Path {
        let rect = bulgeRect(state: state, height: height)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let radius = bulgeCornerRadius(width: rect.width, height: rect.height)
        let flush = flushWeights(state: state)
        return UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius * (1 - flush.bottom), topTrailingRadius: radius * (1 - flush.top),
            style: .continuous
        ).path(in: rect)
    }

    /// Corner radius of a bulge blob `width` wide and `height` tall, shrinking while the blob is
    /// narrower (or shorter) than two radii.
    static func bulgeCornerRadius(width: CGFloat, height: CGFloat = bulgeHeight) -> CGFloat {
        max(min(Theme.bulgeCornerRadius, width / 2, height / 2), 0)
    }

    /// How far the bulge is open, 0 to 1 (overshoot clamps to 1).
    static func openFraction(state: GooState) -> CGFloat {
        min(max(state.bulgeWidth / Theme.bulgeWidth, 0), 1)
    }

    /// The trailing droplets while the bulge travels between rows: two circles hugging the capsule's
    /// left edge between the blob's centre and the lagging `dropletY`. Their radius grows with the lag
    /// and is 0 once the lag closed (the blob settled), so nothing shows at rest. Both centres are the
    /// clamped ones (`PanelModel.bulgeSpan(slot:)`), so the droplets trail the blob that is drawn.
    static func droplets(state: GooState, dropletY: CGFloat) -> [(center: CGPoint, radius: CGFloat)] {
        let lag = dropletY - state.bulgeCenterY
        let size = min(abs(lag) / Theme.dropletFullLag, 1) * Theme.dropletRadius * openFraction(state: state)
        guard size > 0.1 else { return [] }
        let x = capsuleLeft
        return [
            (CGPoint(x: x, y: dropletY), size),
            (CGPoint(x: x - size * 0.6, y: state.bulgeCenterY + lag * 0.5), size * 0.7),
        ]
    }
}
