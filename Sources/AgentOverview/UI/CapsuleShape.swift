import SwiftUI

/// The notch capsule outline: rounded on the left, and at the right (screen) edge the top and
/// bottom edges bend outward into the edge with concave quarter arcs, the way the MacBook notch
/// meets the bezel. The shape is right-aligned in its rect and vertically centred.
///
/// Geometry (y down, W = rect width, body height B, fillet f, corner radius r; the two left corners
/// may have their own radii):
/// the body spans `f ... f + B`; the top edge runs from the top-left corner (radius r) to
/// `(W - f, f)` and then arcs up to `(W, 0)`; mirrored at the bottom. The fillet area between
/// the arc and the screen edge is inside the path, so it is filled with the capsule colour.
///
/// `animatableData` is the body height, so the capsule can grow and shrink with a spring.
/// Both goo renderers draw the capsule part with this path (`GooCanvasView`, `GooPathShape`).
///
/// The geometry above is the right edge's. With `side` `.left` the same outline is mirrored about
/// the rect's centre (`PanelSide.transform(in:)`): rounded on the right, the fillets at the left
/// (screen) edge, "top-left" and "bottom-left" corners then being the top-right and bottom-right ones.
struct CapsuleShape: Shape {
    /// Radius of the two left corners.
    var cornerRadius: CGFloat
    /// Radius of the concave fillets at the screen edge (0 disables them).
    var filletRadius: CGFloat
    /// Height of the body between the fillets.
    var bodyHeight: CGFloat
    /// The top-left corner's radius instead of `cornerRadius` (nil: `cornerRadius`). The goo squares
    /// this corner off while a flush bulge blob absorbs it (`GooLayout.capsuleCornerRadii`).
    var topCornerRadius: CGFloat? = nil
    /// The bottom-left corner's radius instead of `cornerRadius` (nil: `cornerRadius`).
    var bottomCornerRadius: CGFloat? = nil
    /// The screen edge the fillets meet; the rounded corners face away from it.
    var side: PanelSide = .default

    var animatableData: CGFloat {
        get { bodyHeight }
        set { bodyHeight = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = max(bodyHeight, 0)
        let f = max(min(filletRadius, rect.width / 2), 0)
        let r = max(min(topCornerRadius ?? cornerRadius, body / 2, rect.width - f), 0)
        let rb = max(min(bottomCornerRadius ?? cornerRadius, body / 2, rect.width - f), 0)
        let total = body + f * 2
        let top = rect.midY - total / 2
        let bottom = top + total
        let left = rect.minX
        let right = rect.maxX

        var path = Path()
        path.move(to: CGPoint(x: right, y: top))
        // Top fillet: concave arc from the screen edge down into the body's top edge.
        path.addRelativeArc(center: CGPoint(x: right - f, y: top), radius: f, startAngle: .degrees(0), delta: .degrees(90))
        path.addLine(to: CGPoint(x: left + r, y: top + f))
        // Top-left corner.
        path.addRelativeArc(center: CGPoint(x: left + r, y: top + f + r), radius: r, startAngle: .degrees(270), delta: .degrees(-90))
        path.addLine(to: CGPoint(x: left, y: bottom - f - rb))
        // Bottom-left corner.
        path.addRelativeArc(center: CGPoint(x: left + rb, y: bottom - f - rb), radius: rb, startAngle: .degrees(180), delta: .degrees(-90))
        path.addLine(to: CGPoint(x: right - f, y: bottom - f))
        // Bottom fillet: concave arc from the body's bottom edge out to the screen edge.
        path.addRelativeArc(center: CGPoint(x: right - f, y: bottom), radius: f, startAngle: .degrees(270), delta: .degrees(90))
        path.closeSubpath()
        return side.mirror(path, in: rect.minX + rect.maxX)
    }
}
