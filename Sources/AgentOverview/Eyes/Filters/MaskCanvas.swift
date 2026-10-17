import CoreGraphics
import Foundation

/// A square 8 bit RGBA bitmap context for rendering a mask image of a face: `size` points on a
/// display of `scale`. Masks are white (opaque where the face shows through) on transparent.
enum MaskCanvas {
    /// The context and its side in device pixels, or nil for a degenerate size.
    static func make(size: CGFloat, scale: CGFloat) -> (context: CGContext, pixels: Int)? {
        let pixels = Int((size * scale).rounded(.up))
        guard pixels > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        return (context, pixels)
    }
}
