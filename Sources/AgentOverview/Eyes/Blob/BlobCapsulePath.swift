import CoreGraphics
import Foundation

/// A rounded bar centred on the origin with a constant element structure (one move, four
/// lines, four cubic quarter circles, one close), so eyes of any size, a tall capsule or the
/// sliver of a blink, interpolate in Core Animation. When the height is below the width the
/// bar lies flat, which is what a closed eye should be.
enum BlobCapsulePath {
    /// Cubic approximation of a quarter circle.
    private static let kappa = 0.552_284_75

    static func path(width: Double, height: Double, transform: CGAffineTransform) -> CGPath {
        let w = max(width, 0.0001)
        let h = max(height, 0.0001)
        let radius = min(w, h) / 2
        let k = kappa * radius
        let (hw, hh) = (w / 2, h / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -hw + radius, y: -hh))
        path.addLine(to: CGPoint(x: hw - radius, y: -hh))
        path.addCurve(to: CGPoint(x: hw, y: -hh + radius), control1: CGPoint(x: hw - radius + k, y: -hh), control2: CGPoint(x: hw, y: -hh + radius - k))
        path.addLine(to: CGPoint(x: hw, y: hh - radius))
        path.addCurve(to: CGPoint(x: hw - radius, y: hh), control1: CGPoint(x: hw, y: hh - radius + k), control2: CGPoint(x: hw - radius + k, y: hh))
        path.addLine(to: CGPoint(x: -hw + radius, y: hh))
        path.addCurve(to: CGPoint(x: -hw, y: hh - radius), control1: CGPoint(x: -hw + radius - k, y: hh), control2: CGPoint(x: -hw, y: hh - radius + k))
        path.addLine(to: CGPoint(x: -hw, y: -hh + radius))
        path.addCurve(to: CGPoint(x: -hw + radius, y: -hh), control1: CGPoint(x: -hw, y: -hh + radius - k), control2: CGPoint(x: -hw + radius - k, y: -hh))
        path.closeSubpath()
        var t = transform
        return path.copy(using: &t) ?? path
    }
}
