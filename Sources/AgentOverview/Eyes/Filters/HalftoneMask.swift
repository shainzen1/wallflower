import CoreGraphics
import Foundation

/// Pre-rendered halftone screen: a 45 degree dot lattice whose dots are large at the face centre
/// (overlapping into a solid) and thin out toward the rim, the classic shaded-ball halftone.
///
/// Why a mask and not `CIDotScreen` on the layer's `filters`: a dot screen outputs a monochrome
/// black and white pattern (checked on this machine with a flat amber test face: the status colour
/// is gone entirely), and `CICMYKHalftone` turns amber into a red and yellow rosette. A mask keeps
/// the colour exactly and costs the render server nothing. Cached per (size, scale).
@MainActor
enum HalftoneMask {
    private struct Key: Hashable {
        let size: CGFloat
        let scale: CGFloat
    }

    private static var cache: [Key: CGImage] = [:]

    static func image(size: CGFloat, scale: CGFloat) -> CGImage? {
        let key = Key(size: size, scale: scale)
        if let cached = cache[key] { return cached }
        guard let image = render(size: size, scale: scale) else { return nil }
        cache[key] = image
        return image
    }

    private static func render(size: CGFloat, scale: CGFloat) -> CGImage? {
        guard let (context, pixels) = MaskCanvas.make(size: size, scale: scale) else { return nil }
        let pitch = Theme.halftonePitchPixels * Theme.filterPixelFactor(size: size, scale: scale)
        let centre = Double(pixels) / 2
        let half = Double(pixels) / 2
        let count = Int((Double(pixels) / pitch).rounded(.up)) + 2
        let cos45 = 0.5.squareRoot()

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for row in -count...count {
            for column in -count...count {
                let u = Double(column) * pitch
                let v = Double(row) * pitch
                let x = centre + (u - v) * cos45
                let y = centre + (u + v) * cos45
                let distance = min(((x - centre) * (x - centre) + (y - centre) * (y - centre)).squareRoot() / half, 1)
                let fraction = Theme.halftoneCentreRadius + (Theme.halftoneRimRadius - Theme.halftoneCentreRadius) * distance
                let radius = pitch * fraction
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return context.makeImage()
    }
}
