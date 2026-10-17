// Composes the README hero image from a panel snapshot.
//
//   swift docs/assets/make-hero.swift <panel.png> <out.png> [width height]
//
// <panel.png> is what `AgentOverview --snapshot <png>` writes: the panel window rendered over a flat
// grey (`WindowSnapshot.backgroundGray`). This script keys that grey out (the capsule's anti-aliased
// rim becomes partial alpha), paints a soft dark backdrop and places the panel flush with the right
// edge, vertically centred, at its native pixel size. See docs/DEVELOPMENT.md for the whole recipe.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-hero.swift <panel.png> <out.png> [width height]\n".utf8))
    exit(2)
}
let inputURL = URL(filePath: arguments[1])
let outputURL = URL(filePath: arguments[2])
/// 1280 x 760 keeps the 2x panel large where GitHub shows the README (about 880 px wide).
let canvasWidth = arguments.count >= 5 ? Int(arguments[3]) ?? 1280 : 1280
let canvasHeight = arguments.count >= 5 ? Int(arguments[4]) ?? 760 : 760

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: Load the snapshot into an RGBA buffer

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let panel = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(inputURL.path)\n".utf8))
    exit(1)
}
let width = panel.width
let height = panel.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(panel, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// MARK: Key out the flat grey

/// The snapshot's backdrop, read from the top-left corner (the capsule hugs the right edge).
let backdrop = Int(pixels[0])
let tolerance = 2

func isBackdrop(_ index: Int) -> Bool {
    let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
    return abs(r - backdrop) <= tolerance && abs(g - backdrop) <= tolerance && abs(b - backdrop) <= tolerance
}

// Flood fill from the border, so grey pixels inside the capsule (text anti-aliasing) stay opaque.
var outside = [Bool](repeating: false, count: width * height)
var stack: [Int] = []
for x in 0..<width { stack.append(x); stack.append((height - 1) * width + x) }
for y in 0..<height { stack.append(y * width); stack.append(y * width + width - 1) }
while let p = stack.popLast() {
    guard !outside[p], isBackdrop(p * 4) else { continue }
    outside[p] = true
    let x = p % width, y = p / width
    if x > 0 { stack.append(p - 1) }
    if x < width - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - width) }
    if y < height - 1 { stack.append(p + width) }
}

func nearOutside(_ x: Int, _ y: Int, radius: Int) -> Bool {
    for dy in -radius...radius {
        for dx in -radius...radius {
            let nx = x + dx, ny = y + dy
            if nx >= 0, nx < width, ny >= 0, ny < height, outside[ny * width + nx] { return true }
        }
    }
    return false
}

for y in 0..<height {
    for x in 0..<width {
        let p = y * width + x
        let i = p * 4
        if outside[p] {
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            continue
        }
        // The rim: black capsule blended with the grey. Its coverage is how far it is from the grey.
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        let neutral = max(r, g, b) - min(r, g, b) <= 3
        if neutral, max(r, g, b) < backdrop, nearOutside(x, y, radius: 2) {
            let coverage = 1 - Double(max(r, g, b)) / Double(backdrop)
            pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0
            pixels[i + 3] = UInt8((coverage * 255).rounded())
        }
    }
}

let keyed: CGImage = pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

// MARK: Backdrop

/// Painted in floating point, then quantised to 8 bits with an ordered dither, so the dark
/// gradients neither band nor turn into noise that PNG cannot compress.
let backdropContext = CGContext(
    data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 32, bytesPerRow: 0, space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
)!
let full = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

// Rounded corners, so the image reads as a screen on both light and dark pages.
let cornerRadius = CGFloat(min(canvasWidth, canvasHeight)) * 0.03
let screenShape = CGPath(roundedRect: full, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
backdropContext.addPath(screenShape)
backdropContext.clip()

// Ink, a touch lighter toward the right edge.
let base = CGGradient(colorsSpace: sRGB, colors: [color(0x12131D), color(0x1A1C2B)] as CFArray, locations: [0, 1])!
backdropContext.drawLinearGradient(base, start: .zero, end: CGPoint(x: CGFloat(canvasWidth), y: 0), options: [])

// Soft light on the wall where the panel stands, so the black capsule reads against it,
// and two quiet colour fields further out for depth.
func bloom(_ hex: UInt32, alpha: CGFloat, at center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(
        colorsSpace: sRGB, colors: [color(hex, alpha), color(hex, alpha * 0.45), color(hex, 0)] as CFArray, locations: [0, 0.45, 1]
    )!
    backdropContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}
let w = CGFloat(canvasWidth), h = CGFloat(canvasHeight)
bloom(0x5A4C9E, alpha: 0.55, at: CGPoint(x: w * 0.86, y: h * 0.52), radius: w * 0.52)
bloom(0x2C6E86, alpha: 0.30, at: CGPoint(x: w * 0.42, y: h * 0.02), radius: w * 0.42)
bloom(0x7A3F6E, alpha: 0.24, at: CGPoint(x: w * 0.08, y: h * 0.92), radius: w * 0.40)

let canvas = CGContext(
    data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
    space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
if let source = backdropContext.data, let target = canvas.data {
    let floats = source.bindMemory(to: Float.self, capacity: backdropContext.bytesPerRow / 4 * canvasHeight)
    let bytes = target.bindMemory(to: UInt8.self, capacity: canvas.bytesPerRow * canvasHeight)
    let floatRow = backdropContext.bytesPerRow / 4
    for y in 0..<canvasHeight {
        for x in 0..<canvasWidth {
            let threshold = bayer[(y % 4) * 4 + x % 4]
            for c in 0..<4 {
                let value = floats[y * floatRow + x * 4 + c] * 255 + (c == 3 ? 0 : threshold)
                bytes[y * canvas.bytesPerRow + x * 4 + c] = UInt8(clamping: Int(value.rounded()))
            }
        }
    }
}
canvas.addPath(screenShape)
canvas.clip()

// MARK: The panel, flush right, vertically centred, native size

let origin = CGPoint(x: canvasWidth - width, y: (canvasHeight - height) / 2)
canvas.draw(keyed, in: CGRect(origin: origin, size: CGSize(width: width, height: height)))

// MARK: Write

guard let image = canvas.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(outputURL.path) (\(canvasWidth) x \(canvasHeight))")
