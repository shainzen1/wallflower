import CoreGraphics
import Foundation

/// Pre-rendered dot grid used as the mask that turns solid shapes into an LED matrix.
/// Rendered once per (face size, display scale) and cached; the grid is centred on the face
/// so both eyes sit on the same lattice.
@MainActor
enum DotGridMask {
    private struct Key: Hashable {
        let size: CGFloat
        let scale: CGFloat
    }

    private static var cache: [Key: CGImage] = [:]

    /// The mask image for a square face of `size` points on a display of `scale`.
    static func image(size: CGFloat, scale: CGFloat) -> CGImage? {
        let key = Key(size: size, scale: scale)
        if let cached = cache[key] { return cached }
        guard let image = render(size: size, scale: scale) else { return nil }
        cache[key] = image
        return image
    }

    private static func render(size: CGFloat, scale: CGFloat) -> CGImage? {
        guard let (context, pixels) = MaskCanvas.make(size: size, scale: scale) else { return nil }
        let grid = Theme.dotGrid(size: size, scale: scale)
        let pitch = grid.pitch
        let radius = grid.diameter / 2
        let centre = Double(pixels) / 2
        let count = Int((centre / pitch).rounded(.up)) + 1

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for row in -count...count {
            let y = centre + Double(row) * pitch
            for column in -count...count {
                let x = centre + Double(column) * pitch
                context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return context.makeImage()
    }
}
