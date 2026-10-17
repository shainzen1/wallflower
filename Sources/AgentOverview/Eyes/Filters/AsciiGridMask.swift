import CoreGraphics
import CoreText
import Foundation

/// Pre-rendered glyph grid: a monospaced font at a few pixels per cell, one glyph per cell from
/// `Theme.asciiGlyphs` chosen by a seeded pattern (dense glyphs favoured), drawn white on
/// transparent, so the face shows through the letters. At 44 pt the glyphs are 3 to 4 px smudges
/// that read as a text texture; at 120 pt the letters become readable.
///
/// This is a fixed glyph lattice, not an ASCII renderer: a true brightness-to-glyph filter would
/// need a fragment shader (Metal), which cannot be compiled without Xcode. A faint floor between
/// the glyphs keeps the silhouette readable. Cached per (size, scale).
@MainActor
enum AsciiGridMask {
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

    /// The glyph for a cell: a seeded unit value, biased toward the dense glyphs at the front of the set.
    static func glyph(row: Int, column: Int) -> Character {
        let glyphs = Theme.asciiGlyphs
        let unit = SeedHash("ascii-\(row)-\(column)").unit(0)
        let index = Int(pow(unit, Theme.asciiDensityBias) * Double(glyphs.count))
        return glyphs[min(index, glyphs.count - 1)]
    }

    private static func render(size: CGFloat, scale: CGFloat) -> CGImage? {
        guard let (context, pixels) = MaskCanvas.make(size: size, scale: scale) else { return nil }
        let pitch = Theme.asciiCellPixels * Theme.filterPixelFactor(size: size, scale: scale)
        let fontSize = pitch * Theme.asciiGlyphScale
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let white = CGColor(gray: 1, alpha: 1)
        let count = Int((Double(pixels) / pitch).rounded(.up)) + 1

        context.setFillColor(CGColor(gray: 1, alpha: Theme.asciiFloorOpacity))
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.setFillColor(white)
        for row in 0..<count {
            for column in 0..<count {
                let text = NSAttributedString(
                    string: String(glyph(row: row, column: column)),
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
                    ]
                )
                let line = CTLineCreateWithAttributedString(text)
                let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
                let x = Double(column) * pitch + (pitch - bounds.width) / 2 - bounds.minX
                let y = Double(row) * pitch + (pitch - bounds.height) / 2 - bounds.minY
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
            }
        }
        return context.makeImage()
    }
}
