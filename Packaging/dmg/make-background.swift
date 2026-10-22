// Draws the disk image's window background: black, an arrow from the app to Applications, a grey
// chip under each icon label and a one-line hint. Writes background.png (1x) and background@2x.png
// next to this script; commit both. Positions match the icon locations in layout.py.
//
//   swift Packaging/dmg/make-background.swift
//
// The chips are there because Finder draws the labels in the system appearance's text colour,
// black in light mode and white in dark mode, whatever the picture behind them. A mid grey reads
// with both.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The Finder window's content size in points (layout.py, window_rect).
let width: CGFloat = 640
let height: CGFloat = 400
/// Icon centres, top-left origin (layout.py, icon_locations).
let appCenter = CGPoint(x: 160, y: 180)
let applicationsCenter = CGPoint(x: 480, y: 180)
/// Finder's label for a 128 pt icon with 13 pt text sits about this far below the icon centre.
let labelOffset: CGFloat = 77

let folder = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// The capsule's black, a soft lift where the icons stand, the idle face's warm grey for the chips.
let ink: UInt32 = 0x0A0A0B
let lift: UInt32 = 0x1A1A1C
let chip: UInt32 = 0x8C8981
let arrow: UInt32 = 0x5E5C57
let hint: UInt32 = 0x8C8981

func render(scale: CGFloat) -> CGImage {
    let pixelWidth = Int(width * scale), pixelHeight = Int(height * scale)

    // The backdrop in floating point, quantised with an ordered dither so the dark gradient does not band.
    let backdrop = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 32, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    backdrop.scaleBy(x: scale, y: scale)
    backdrop.setFillColor(color(ink))
    backdrop.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let glow = CGGradient(colorsSpace: sRGB, colors: [color(lift), color(lift, 0.5), color(lift, 0)] as CFArray, locations: [0, 0.5, 1])!
    let glowCenter = CGPoint(x: width / 2, y: height - appCenter.y)
    backdrop.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: width * 0.55, options: [])

    let canvas = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
    if let source = backdrop.data, let target = canvas.data {
        let floats = source.bindMemory(to: Float.self, capacity: backdrop.bytesPerRow / 4 * pixelHeight)
        let bytes = target.bindMemory(to: UInt8.self, capacity: canvas.bytesPerRow * pixelHeight)
        let floatRow = backdrop.bytesPerRow / 4
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let threshold = bayer[(y % 4) * 4 + x % 4]
                for c in 0..<4 {
                    let value = floats[y * floatRow + x * 4 + c] * 255 + (c == 3 ? 0 : threshold)
                    bytes[y * canvas.bytesPerRow + x * 4 + c] = UInt8(clamping: Int(value.rounded()))
                }
            }
        }
    }

    // From here on, points with the origin at the top left, like Finder's icon locations.
    canvas.scaleBy(x: scale, y: scale)
    canvas.translateBy(x: 0, y: height)
    canvas.scaleBy(x: 1, y: -1)

    // Label chips: capsules, wide enough for "Wallflower.app" when extensions are shown.
    canvas.setFillColor(color(chip))
    for center in [appCenter, applicationsCenter] {
        let rect = CGRect(x: center.x - 62, y: center.y + labelOffset - 12, width: 124, height: 24)
        canvas.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        canvas.fillPath()
    }

    // The arrow, between the icons' edges with some air.
    let start = CGPoint(x: appCenter.x + 96, y: appCenter.y)
    let end = CGPoint(x: applicationsCenter.x - 96, y: applicationsCenter.y)
    canvas.setStrokeColor(color(arrow))
    canvas.setLineWidth(2)
    canvas.setLineCap(.round)
    canvas.setLineJoin(.round)
    canvas.move(to: start)
    canvas.addLine(to: end)
    canvas.move(to: CGPoint(x: end.x - 9, y: end.y - 9))
    canvas.addLine(to: end)
    canvas.addLine(to: CGPoint(x: end.x - 9, y: end.y + 9))
    canvas.strokePath()

    // The hint, centred under the row, well above the bottom edge (in case a title bar crops it).
    let font = CTFontCreateUIFontForLanguage(.system, 13, nil)!
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hint),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Drag Wallflower to Applications", attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    canvas.saveGState()
    // CoreText draws with the y axis up: flip back locally around the baseline.
    let baseline = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: 330)
    canvas.translateBy(x: baseline.x, y: baseline.y)
    canvas.scaleBy(x: 1, y: -1)
    canvas.textPosition = .zero
    CTLineDraw(line, canvas)
    canvas.restoreGState()

    return canvas.makeImage()!
}

func write(_ image: CGImage, dpi: CGFloat, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
    let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    print("wrote \(url.path) (\(image.width) x \(image.height))")
}

write(render(scale: 1), dpi: 72, to: folder.appending(path: "background.png"))
write(render(scale: 2), dpi: 144, to: folder.appending(path: "background@2x.png"))
