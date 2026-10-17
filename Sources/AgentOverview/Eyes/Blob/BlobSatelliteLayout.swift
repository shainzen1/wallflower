import CoreGraphics
import Foundation

/// Geometry of the subagent satellites: how many to show, where each sits on the orbit
/// ellipse for a phase, the orbit path the render server follows, and the satellite's own
/// silhouette. Pure functions in face coordinates (a `size` square, y up), so the layer tree
/// only places layers and the tests can check the bounds.
enum BlobSatelliteLayout {
    /// Satellites shown for a subagent count: never more than `Theme.satelliteMax`.
    static func count(for subagents: Int) -> Int {
        min(max(subagents, 0), Theme.satelliteMax)
    }

    /// Evenly spaced phases in [0, 1) for a fresh set of `count` satellites.
    static func phases(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { Double($0) / Double(count) }
    }

    /// The phase for one more satellite next to `existing` ones that keep theirs: the middle of
    /// the largest gap on the circle (so 1, 2 and 4 satellites end up evenly spaced).
    static func nextPhase(existing: [Double]) -> Double {
        let sorted = existing.map { $0 - $0.rounded(.down) }.sorted()
        guard let first = sorted.first else { return 0 }
        var bestStart = sorted[sorted.count - 1]
        var bestGap = first + 1 - bestStart
        for index in 0..<(sorted.count - 1) {
            let gap = sorted[index + 1] - sorted[index]
            // On a tie the earlier gap wins, so 0 and 0.5 get 0.25, then 0.75.
            if gap >= bestGap - 0.000_001 {
                bestGap = gap
                bestStart = sorted[index]
            }
        }
        let phase = bestStart + bestGap / 2
        return phase - phase.rounded(.down)
    }

    /// Satellite diameter for a face size.
    static func diameter(size: CGFloat) -> CGFloat {
        size * Theme.satelliteSize
    }

    /// Orbit radii (horizontal, vertical) for a face size.
    static func radii(size: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let x = size * Theme.satelliteOrbitRadius
        return (x, x * Theme.satelliteOrbitAspect)
    }

    /// Farthest a satellite's edge gets from the face centre, horizontally and vertically.
    static func extent(size: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let radii = radii(size: size)
        let half = diameter(size: size) / 2
        return (radii.x + half, radii.y + half)
    }

    /// Centre of a satellite at `phase` (0 is the right end of the ellipse, increasing counter-clockwise).
    static func position(phase: Double, size: CGFloat) -> CGPoint {
        let radii = radii(size: size)
        let angle = phase * 2 * .pi
        return CGPoint(x: size / 2 + radii.x * cos(angle), y: size / 2 + radii.y * sin(angle))
    }

    /// The orbit: one closed ellipse starting at phase 0 and running counter-clockwise, so an
    /// animation along it with `timeOffset = phase * period` starts where `position(phase:)` says.
    static func orbitPath(size: CGFloat) -> CGPath {
        let radii = radii(size: size)
        let transform = CGAffineTransform(translationX: size / 2, y: size / 2).scaledBy(x: radii.x, y: radii.y)
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: 2 * .pi, clockwise: false, transform: transform)
        path.closeSubpath()
        return path
    }

    /// The satellite body: a disc filling its layer.
    static func bodyPath(size: CGFloat) -> CGPath {
        let d = diameter(size: size)
        return CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)
    }

    /// Two tiny dots as eyes, in the satellite's layer coordinates (y up).
    static func eyesPath(size: CGFloat) -> CGPath {
        let d = diameter(size: size)
        let eye = d * Theme.satelliteEyeDiameter
        let spacing = d * Theme.satelliteEyeSpacing
        let y = d / 2 + d * Theme.satelliteEyeLift
        let path = CGMutablePath()
        for x in [d / 2 - spacing / 2, d / 2 + spacing / 2] {
            path.addEllipse(in: CGRect(x: x - eye / 2, y: y - eye / 2, width: eye, height: eye))
        }
        return path
    }
}
