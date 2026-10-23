import SwiftUI

/// The `.path` goo renderer: one `Shape` carrying the same animatable `GooState` as the Canvas.
/// The capsule (`CapsuleShape`) is united with the bulge blob and two concave fillet pieces of
/// `Theme.bulgeFilletRadius` where the blob's top and bottom edges meet the capsule's left side.
/// Cleanly anti-aliased, cheapest, less liquid: no droplets.
///
/// The blob is placed by `GooLayout.bulgeSpan(state:height:)`, so it stays `Theme.bulgeEdgeMargin`
/// inside the body. Its left corners are rounded; its right side is square and reaches
/// `Theme.bulgeOverlap` into the capsule, so no notch opens where it meets the capsule. A fillet
/// meets the capsule's straight left edge, or, near the body's ends, the rounded corner (tangent to
/// the corner's arc), so the join is concave everywhere.
///
/// At the first and last slot the blob is flush (`GooLayout.bulgeSpan`): its edge lies on the
/// body's, the capsule's corner on that side is square under it (`GooLayout.capsuleCornerRadii`) and
/// the fillet is empty, so the outline is one straight line from the blob's rounded corner to the
/// screen-edge fillet. All of it springs with `GooState.bulgeTopFlush` and `bulgeBottomFlush`.
///
/// The outline is built for the right edge (`canonicalPath(in:)`); on the left side `path(in:)`
/// mirrors it about the rect's centre, so the bulge grows rightward out of a capsule on the left edge.
struct GooPathShape: Shape {
    var state: GooState
    let capsuleHeight: CGFloat
    /// The screen edge the capsule meets.
    var side: PanelSide = .default

    var animatableData: GooState {
        get { state }
        set { state = newValue }
    }

    func path(in rect: CGRect) -> Path {
        side.mirror(canonicalPath(in: rect), in: rect.minX + rect.maxX)
    }

    /// The outline on the right edge: the capsule flush with the rect's right edge, the bulge to its left.
    func canonicalPath(in rect: CGRect) -> Path {
        let capsuleRect = GooLayout.capsuleRect(state: state, height: capsuleHeight).offsetBy(dx: rect.minX, dy: rect.minY)
        let edgeFillet = GooLayout.edgeFilletRadius(bodyHeight: state.bodyHeight)
        // Visible bulge: the blob minus its overlap with the capsule.
        let reach = state.bulgeWidth - Theme.bulgeOverlap
        guard reach > 0.5 else {
            return CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: edgeFillet, bodyHeight: state.bodyHeight)
                .path(in: capsuleRect)
        }
        // On a flush side the capsule's corner squares off under the blob (`GooLayout.capsuleCornerRadii`).
        var path = GooLayout.capsuleShape(state: state, filletRadius: edgeFillet).path(in: capsuleRect)

        let body = GooLayout.bodySpan(height: capsuleHeight, bodyHeight: state.bodyHeight)
        let bodyTop = body.lowerBound + rect.minY
        let bodyBottom = body.upperBound + rect.minY
        // The corner radii `CapsuleShape` draws with.
        let corners = GooLayout.capsuleCornerRadii(state: state)
        let limit = min((bodyBottom - bodyTop) / 2, capsuleRect.width - edgeFillet)
        let rTop = max(min(corners.top, limit), 0)
        let rBottom = max(min(corners.bottom, limit), 0)
        let left = capsuleRect.minX
        let span = GooLayout.bulgeSpan(state: state, height: capsuleHeight)
        let top = span.minY + rect.minY
        let bottom = span.maxY + rect.minY
        guard bottom - top > 0.5 else { return path }

        let radius = GooLayout.bulgeCornerRadius(width: reach, height: bottom - top)
        let blob = UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: radius, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous
        ).path(in: CGRect(x: left - reach, y: top, width: reach + Theme.bulgeOverlap, height: bottom - top))
        path = path.union(blob)

        let fillet = min(Theme.bulgeFilletRadius, reach / 2)
        guard fillet > 0.5 else { return path }
        // A flush edge is collinear with the body's: its fillet is empty, the edge one straight line.
        path = path.union(Self.fillet(left: left, bodyTop: bodyTop, cornerRadius: rTop, edgeY: top, radius: fillet))
        // The bottom one is the top one mirrored: computed upside down, then flipped back.
        let flip = CGAffineTransform(scaleX: 1, y: -1)
        path = path.union(Self.fillet(left: left, bodyTop: -bodyBottom, cornerRadius: rBottom, edgeY: -bottom, radius: fillet).applying(flip))
        return path
    }

    /// The concave fillet piece above a blob whose top edge is `edgeY`, against a capsule whose left
    /// side is the line `x = left` with a top-left corner of `cornerRadius` at `bodyTop` (y down).
    /// The fillet disc of `radius` rests on the blob's edge and touches the capsule's straight side or,
    /// higher up, the corner's arc (externally tangent); the piece is the corner between the two
    /// tangent points less the disc. A square corner (`cornerRadius` 0) is an arc of radius 0: the
    /// disc then passes through the corner point, so as the blob's edge rises to the body's top the
    /// piece shrinks to nothing. Empty when the edge is not below the body's top: a flush edge is
    /// collinear with the body's, and the outline runs straight on.
    static func fillet(left: CGFloat, bodyTop: CGFloat, cornerRadius r: CGFloat, edgeY: CGFloat, radius rho: CGFloat) -> Path {
        guard rho > 0, r >= 0, edgeY > bodyTop else { return Path() }
        let centreY = edgeY - rho
        let corner = CGPoint(x: left + r, y: bodyTop + r)
        let piece: Path
        let disc: CGPoint
        if centreY >= corner.y {
            // Against the straight side: the classic square minus a quarter disc.
            disc = CGPoint(x: left - rho, y: centreY)
            piece = Path(CGRect(x: left - rho, y: centreY, width: rho, height: rho))
        } else {
            // Against the corner's arc: the disc's centre is `r + rho` from the corner's centre.
            let dy = corner.y - centreY
            let d = r + rho
            guard d > dy else { return Path() }
            disc = CGPoint(x: corner.x - (d * d - dy * dy).squareRoot(), y: centreY)
            let touch = CGPoint(x: corner.x + (disc.x - corner.x) * r / d, y: corner.y + (disc.y - corner.y) * r / d)
            var triangle = Path()
            triangle.move(to: CGPoint(x: disc.x, y: edgeY))
            triangle.addLine(to: CGPoint(x: touch.x, y: edgeY))
            triangle.addLine(to: touch)
            triangle.closeSubpath()
            piece = triangle
        }
        return piece.subtracting(Path(ellipseIn: CGRect(x: disc.x - rho, y: disc.y - rho, width: rho * 2, height: rho * 2)))
    }
}
