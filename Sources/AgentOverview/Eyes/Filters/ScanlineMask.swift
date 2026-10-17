import CoreGraphics
import Foundation

/// Pre-rendered horizontal scanlines: `Theme.scanlineOnFraction` of every pitch is lit, the gap
/// keeps `Theme.scanlineGapOpacity` so the face stays readable at 44 pt. A mask image rather
/// than `CILineScreen`: the line screen is monochrome and would drop the status colour, and a
/// mask costs the render server nothing. Cached per (size, scale) like the dot grid.
@MainActor
enum ScanlineMask {
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
        let pitch = Theme.scanlinePitchPixels * Theme.filterPixelFactor(size: size, scale: scale)
        let lit = pitch * Theme.scanlineOnFraction
        context.setFillColor(CGColor(gray: 1, alpha: Theme.scanlineGapOpacity))
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        var y = 0.0
        while y < Double(pixels) {
            context.fill(CGRect(x: 0, y: y, width: Double(pixels), height: lit))
            y += pitch
        }
        return context.makeImage()
    }
}
