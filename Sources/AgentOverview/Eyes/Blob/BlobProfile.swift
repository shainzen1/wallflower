import CoreGraphics
import Foundation

/// A body silhouette as a radial profile: one radius (fraction of the face size) for each of
/// `sampleCount` evenly spaced angles, angle 0 pointing right and increasing counter-clockwise
/// in layer coordinates (y up), so index 16 is the top. Every profile shares the angles, which
/// makes a morph a plain lerp of the radii and keeps the path's element count constant, so Core
/// Animation can interpolate it.
struct BlobProfile: Equatable, Sendable {
    static let sampleCount = 64

    var radii: [Double]

    /// Angle of sample `index`.
    static func angle(_ index: Int) -> Double {
        Double(index) / Double(sampleCount) * 2 * .pi
    }

    /// A profile from a radius-of-angle formula.
    init(_ radius: (Double) -> Double) {
        radii = (0..<Self.sampleCount).map { radius(Self.angle($0)) }
    }

    /// A profile from an inside test on a region that contains the origin: the farthest point
    /// on each ray that is still inside (a coarse scan outward from the rim, then a bisection).
    /// Used for silhouettes that are unions of circles, like the cloud. Runs once per shape.
    init(inside: (Double, Double) -> Bool, reach: Double = 0.5) {
        let steps = 240
        radii = (0..<Self.sampleCount).map { index in
            let angle = Self.angle(index)
            let (dx, dy) = (cos(angle), sin(angle))
            var outside = reach
            var insideDistance = 0.0
            for step in stride(from: steps, through: 1, by: -1) {
                let t = reach * Double(step) / Double(steps)
                if inside(dx * t, dy * t) {
                    insideDistance = t
                    outside = reach * Double(step + 1) / Double(steps)
                    break
                }
            }
            for _ in 0..<20 {
                let mid = (insideDistance + outside) / 2
                if inside(dx * mid, dy * mid) { insideDistance = mid } else { outside = mid }
            }
            return insideDistance
        }
    }

    init(radii: [Double]) {
        precondition(radii.count == Self.sampleCount)
        self.radii = radii
    }

    /// Linear blend of two profiles.
    static func lerp(_ a: BlobProfile, _ b: BlobProfile, t: Double) -> BlobProfile {
        BlobProfile(radii: zip(a.radii, b.radii).map { $0 + ($1 - $0) * t })
    }

    /// The radius at any angle, interpolated between the two neighbouring samples.
    func radius(at angle: Double) -> Double {
        let count = Double(Self.sampleCount)
        var position = angle / (2 * .pi) * count
        position = position - (position / count).rounded(.down) * count
        let lower = Int(position) % Self.sampleCount
        let upper = (lower + 1) % Self.sampleCount
        let fraction = position - Double(Int(position))
        return radii[lower] + (radii[upper] - radii[lower]) * fraction
    }

    /// The profile scaled vertically by `factor` (the capsule flattening, the sleepy sag).
    /// Exact for star shaped outlines: each sample angle is mapped back to the angle it came from.
    func squashed(_ factor: Double) -> BlobProfile {
        guard factor != 1 else { return self }
        return BlobProfile { angle in
            let source = atan2(sin(angle) / factor, cos(angle))
            let r = radius(at: source)
            return r * (cos(source) * cos(source) + factor * factor * sin(source) * sin(source)).squareRoot()
        }
    }

    /// The closed cubic path of the silhouette, centred in a `size` square: one move, one curve
    /// per sample (Catmull-Rom tangents), one close. Constant element count across every profile.
    func path(size: CGFloat) -> CGPath {
        let n = Self.sampleCount
        let centre = Double(size) / 2
        let points: [CGPoint] = (0..<n).map { index in
            let angle = Self.angle(index)
            return CGPoint(x: centre + radii[index] * Double(size) * cos(angle), y: centre + radii[index] * Double(size) * sin(angle))
        }
        let tension = Theme.blobCurveTension / 6
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension, y: p1.y + (p2.y - p0.y) * tension)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension, y: p2.y - (p3.y - p1.y) * tension)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
