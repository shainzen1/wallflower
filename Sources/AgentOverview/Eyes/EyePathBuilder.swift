import CoreGraphics
import Foundation

/// Turns `EyeParameters` into a `CGPath` for one eye inside a square face of a given size.
///
/// Construction (local eye coordinates: origin at the eye centre, +x toward the nose, +y down):
///
/// 1. The eye is a box of `width` x `height`. The top and bottom edges tilt about their
///    midpoints by `topSlope` / `bottomSlope` (fraction of the half height), so the four
///    sharp corners are TL, TR, BR, BL with the inner corners moved by +slope and the outer
///    corners by -slope.
/// 2. Each corner is rounded with one cubic curve: the curve starts `r` before the corner
///    on the incoming edge and ends `r` after it on the outgoing edge, with both control
///    points pulled toward the corner by the usual circle factor (0.5523). `r` comes from
///    `topRadius` / `bottomRadius` times the smaller half extent and is clamped so the two
///    radii on a side never overlap.
/// 3. The top and bottom edges each carry one concave "bite": a single cubic between two
///    points on the edge, `inverseRadius` times the half width either side of the edge
///    midpoint, whose control points sit 4/3 of `inverseOffset` times the height inside
///    the eye, so the curve dips exactly `inverseOffset` deep at its middle. A bite with
///    zero width or depth collapses to a point on the edge, but the elements stay.
/// 4. The path is emitted as: move, [TL corner curve], line, [top bite curve], line,
///    [TR corner curve], line, [BR corner curve], line, [bottom bite curve], line,
///    [BL corner curve], line, close. That is 14 elements in the same order for every
///    parameter set, which is what lets Core Animation interpolate `path` between poses.
/// 5. A final affine transform maps local coordinates to layer coordinates (y up): it
///    mirrors x for the right eye, flips y, and moves the origin to the eye centre
///    (`Theme.eyeSpacing` apart, `Theme.eyeVerticalOffset` above the face centre, plus
///    the parameter offsets).
enum EyePathBuilder {
    /// Control point pull for a 90 degree circular corner approximated by one cubic.
    private static let kappa: Double = 0.5523

    /// Builds the path for one eye.
    /// - Parameters:
    ///   - parameters: the eye shape.
    ///   - faceSize: side of the square face the eye lives in, in points.
    ///   - mirrored: `false` for the left eye, `true` for the right eye (mirror image).
    static func path(for parameters: EyeParameters, faceSize: CGFloat, mirrored: Bool) -> CGPath {
        let geometry = Geometry(parameters: parameters, faceSize: Double(faceSize))
        let transform = layerTransform(parameters: parameters, faceSize: Double(faceSize), mirrored: mirrored)
        return geometry.makePath(transform: transform)
    }

    /// Maps local eye coordinates (+x inner, +y down) to layer coordinates (+y up) for the given eye.
    private static func layerTransform(parameters: EyeParameters, faceSize: Double, mirrored: Bool) -> CGAffineTransform {
        let sx: Double = mirrored ? -1 : 1
        // The left eye sits left of centre; +x (inner) points right for it and left for the mirrored eye.
        let centreX = faceSize / 2 - sx * (Theme.eyeSpacing * faceSize / 2) + sx * parameters.offsetX * faceSize
        let centreY = faceSize / 2 + Theme.eyeVerticalOffset * faceSize - parameters.offsetY * faceSize
        return CGAffineTransform(a: sx, b: 0, c: 0, d: -1, tx: centreX, ty: centreY)
    }

    /// All points of one eye in local coordinates, computed once per path.
    private struct Geometry {
        struct Corner {
            let entry: CGPoint
            let exit: CGPoint
            let control1: CGPoint
            let control2: CGPoint
        }

        struct Bite {
            let start: CGPoint
            let end: CGPoint
            let control1: CGPoint
            let control2: CGPoint
        }

        let topLeft: Corner
        let topRight: Corner
        let bottomRight: Corner
        let bottomLeft: Corner
        let topBite: Bite
        let bottomBite: Bite

        init(parameters p: EyeParameters, faceSize s: Double) {
            let w = max(p.width, 0.02) * s
            let h = max(p.height, 0.02) * s
            let hw = w / 2
            let hh = h / 2
            let ts = clamp(p.topSlope, -1, 1)
            let bs = clamp(p.bottomSlope, -1, 1)

            // Sharp corners. Inner corners (+x) move by +slope, outer corners by -slope.
            let tlS = CGPoint(x: -hw, y: -hh - ts * hh)
            let trS = CGPoint(x: hw, y: -hh + ts * hh)
            let brS = CGPoint(x: hw, y: hh - bs * hh)
            let blS = CGPoint(x: -hw, y: hh + bs * hh)

            // Corner radii, clamped so they never overlap on a side.
            let unit = min(hw, hh)
            var rt = clamp(p.topRadius, 0, 1) * unit
            var rb = clamp(p.bottomRadius, 0, 1) * unit
            let shortestSide = max(min(blS.y - tlS.y, brS.y - trS.y), 0.001)
            if rt + rb > shortestSide {
                let k = shortestSide / (rt + rb)
                rt *= k
                rb *= k
            }

            topLeft = Geometry.corner(at: tlS, from: blS, to: trS, radius: rt)
            topRight = Geometry.corner(at: trS, from: tlS, to: brS, radius: rt)
            bottomRight = Geometry.corner(at: brS, from: trS, to: blS, radius: rb)
            bottomLeft = Geometry.corner(at: blS, from: brS, to: tlS, radius: rb)

            let maxDepth = h * Theme.maxInverseDepth
            topBite = Geometry.bite(
                edgeStart: topLeft.exit, edgeEnd: topRight.entry,
                lineStart: tlS, lineEnd: trS,
                halfWidth: clamp(p.topInverseRadius, 0, 1) * hw,
                depth: min(clamp(p.topInverseOffset, 0, 1) * h, maxDepth),
                direction: 1
            )
            bottomBite = Geometry.bite(
                edgeStart: bottomRight.exit, edgeEnd: bottomLeft.entry,
                lineStart: brS, lineEnd: blS,
                halfWidth: clamp(p.bottomInverseRadius, 0, 1) * hw,
                depth: min(clamp(p.bottomInverseOffset, 0, 1) * h, maxDepth),
                direction: -1
            )
        }

        /// One rounded corner: enters `radius` before the sharp corner, leaves `radius` after it.
        private static func corner(at c: CGPoint, from a: CGPoint, to b: CGPoint, radius r: Double) -> Corner {
            let entry = c.moved(toward: a, by: r)
            let exit = c.moved(toward: b, by: r)
            return Corner(
                entry: entry,
                exit: exit,
                control1: entry.moved(toward: c, by: r * kappa),
                control2: exit.moved(toward: c, by: r * kappa)
            )
        }

        /// One concave bite centred on the edge midpoint. `direction` is +1 when the bite dips
        /// toward +y (top edge) and -1 when it rises toward -y (bottom edge).
        private static func bite(
            edgeStart: CGPoint, edgeEnd: CGPoint,
            lineStart: CGPoint, lineEnd: CGPoint,
            halfWidth: Double, depth: Double, direction: Double
        ) -> Bite {
            let span = abs(edgeEnd.x - edgeStart.x) / 2
            let midX = (edgeStart.x + edgeEnd.x) / 2
            let a = (halfWidth < 0.001 || depth < 0.001) ? 0 : min(halfWidth, span)
            let d = a == 0 ? 0 : depth
            // Travel direction along the edge: +1 left to right, -1 right to left.
            let along: Double = edgeEnd.x >= edgeStart.x ? 1 : -1
            func yOnLine(_ x: Double) -> Double {
                guard lineEnd.x != lineStart.x else { return lineStart.y }
                let t = (x - lineStart.x) / (lineEnd.x - lineStart.x)
                return lineStart.y + (lineEnd.y - lineStart.y) * t
            }
            let x1 = midX - along * a
            let x2 = midX + along * a
            let cx1 = midX - along * a / 3
            let cx2 = midX + along * a / 3
            let bulge = direction * d * 4 / 3
            return Bite(
                start: CGPoint(x: x1, y: yOnLine(x1)),
                end: CGPoint(x: x2, y: yOnLine(x2)),
                control1: CGPoint(x: cx1, y: yOnLine(cx1) + bulge),
                control2: CGPoint(x: cx2, y: yOnLine(cx2) + bulge)
            )
        }

        /// Emits the 14 elements. The order never changes.
        func makePath(transform t: CGAffineTransform) -> CGPath {
            let path = CGMutablePath()
            path.move(to: topLeft.entry, transform: t)
            path.addCurve(to: topLeft.exit, control1: topLeft.control1, control2: topLeft.control2, transform: t)
            path.addLine(to: topBite.start, transform: t)
            path.addCurve(to: topBite.end, control1: topBite.control1, control2: topBite.control2, transform: t)
            path.addLine(to: topRight.entry, transform: t)
            path.addCurve(to: topRight.exit, control1: topRight.control1, control2: topRight.control2, transform: t)
            path.addLine(to: bottomRight.entry, transform: t)
            path.addCurve(to: bottomRight.exit, control1: bottomRight.control1, control2: bottomRight.control2, transform: t)
            path.addLine(to: bottomBite.start, transform: t)
            path.addCurve(to: bottomBite.end, control1: bottomBite.control1, control2: bottomBite.control2, transform: t)
            path.addLine(to: bottomLeft.entry, transform: t)
            path.addCurve(to: bottomLeft.exit, control1: bottomLeft.control1, control2: bottomLeft.control2, transform: t)
            path.addLine(to: topLeft.entry, transform: t)
            path.closeSubpath()
            return path
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}

private extension CGPoint {
    /// The point `distance` along the straight line from here toward `target` (stays here if they coincide).
    func moved(toward target: CGPoint, by distance: Double) -> CGPoint {
        let dx = target.x - x
        let dy = target.y - y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.000_001 else { return self }
        return CGPoint(x: x + dx / len * distance, y: y + dy / len * distance)
    }
}
