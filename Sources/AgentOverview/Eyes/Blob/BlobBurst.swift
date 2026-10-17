import CoreGraphics
import Foundation

/// The geometry of the done burst: `Theme.doneBurstCount` tiny dots leave the face centre on
/// evenly spaced rays (the first one pointing up-right, so none runs straight along an axis),
/// from `Theme.doneBurstStart` to `Theme.doneBurstDistance` of the face size.
enum BlobBurst {
    /// Where each dot starts and ends, relative to the face centre, for a face of `size`.
    static func rays(size: CGFloat) -> [(start: CGPoint, end: CGPoint)] {
        let count = Theme.doneBurstCount
        return (0..<count).map { index in
            let angle = (Double(index) + 0.5) / Double(count) * 2 * .pi
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            return (
                CGPoint(x: direction.x * size * Theme.doneBurstStart, y: direction.y * size * Theme.doneBurstStart),
                CGPoint(x: direction.x * size * Theme.doneBurstDistance, y: direction.y * size * Theme.doneBurstDistance)
            )
        }
    }

    /// One dot, centred on the origin of its layer's bounds.
    static func dotPath(size: CGFloat) -> CGPath {
        let diameter = size * Theme.doneBurstDotSize
        return CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter), transform: nil)
    }
}
