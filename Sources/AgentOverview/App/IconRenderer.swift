import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `--render-icon <folder>`: writes the app icon as an `.iconset` (every size `iconutil` wants),
/// drawn with Core Graphics from the face renderer's own geometry (`BlobProfile`, `BlobEyes`,
/// `BlobExpressions`, the `Theme` colours), so the icon and the faces in the panel are the same
/// object. `scripts/make-icon.sh` runs it and turns the folder into `Packaging/AppIcon.icns`.
///
/// Layout on the macOS 26 grid (1024 canvas): a continuous-corner rounded square of 824 centred,
/// near black with a subtle vertical gradient, a faint inner highlight along the top edge and the
/// template's soft drop shadow. On it one large face: the idle pill with normal eyes in the done
/// mint, glancing left (toward the screen, as a face at the right edge would), with a soft glow of
/// its colour behind it. It sits a little low, and a little right so the glance has room.
enum IconRenderer {
    /// The `--render-icon` folder, when the flag is present.
    static func requestedFolder(in arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(index + 1) else { return nil }
        return URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
    }

    /// Writes the iconset and returns the process exit code.
    static func run(folder: URL) -> Int32 {
        do {
            try writeIconset(to: folder)
            print("\(AppInfo.name): icon set written to \(folder.path)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(AppInfo.name): --render-icon failed: \(error)\n".utf8))
            return 1
        }
    }

    // MARK: Look

    /// Side of the reference canvas; every length below is in its pixels.
    static let canvas: CGFloat = 1024
    /// The rounded square of the macOS grid and its continuous corner radius.
    static let bodySide: CGFloat = 824
    static let bodyCornerRadius: CGFloat = 185
    /// Body gradient, top to bottom (sRGB #141416 to #000000).
    static let bodyTop = EyeColor(name: "icon top", red: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255)
    static let bodyBottom = EyeColor(name: "icon bottom", red: 0, green: 0, blue: 0)
    /// The inner highlight along the top edge: width, white alpha at the very top, and how far down
    /// (fraction of the side) it fades out.
    static let highlightWidth: CGFloat = 2
    static let highlightAlpha: Double = 0.16
    static let highlightReach: CGFloat = 0.35
    /// The drop shadow under the rounded square (macOS template: black, offset down, soft).
    static let shadowOffset: CGFloat = 10
    static let shadowBlur: CGFloat = 20
    static let shadowAlpha: Double = 0.30
    /// At this pixel size and below the look simplifies (`look(forPixels:)`), so it still reads.
    static let smallPixels = 32

    /// What sits on the rounded square. Lengths are reference pixels, the centre is y up.
    struct Look: Sendable {
        var body = BlobBody(shape: Theme.blobIdleShape)
        /// Normal eyes glancing left and a touch up: curious, not shy.
        var pose = BlobExpressions.pose(for: .normal).looking(yaw: -20, pitch: 3)
        var color = Theme.justFinishedColor
        /// Side of the face square and its centre.
        var faceSize: CGFloat = 580
        var faceCentre = CGPoint(x: 520, y: 488)
        /// Soft glow of the face colour behind it, alpha at the centre (0 for none), and its radius.
        var glowAlpha: Double = 0.16
        var glowRadius: CGFloat = 420
        var highlight = true
    }

    /// The look at a pixel size: the small sizes get a bigger face, a softer glance (the far eye
    /// would thin to a grey sliver) and no glow or highlight.
    static func look(forPixels pixels: Int) -> Look {
        var look = Look()
        if pixels <= smallPixels {
            look.pose = look.pose.looking(yaw: -10, pitch: look.pose.pitch)
            look.faceSize = 660
            look.faceCentre = CGPoint(x: canvas / 2, y: 496)
            look.glowAlpha = 0
            look.highlight = false
        }
        return look
    }

    // MARK: Output

    /// The iconset entries: file name and pixel size.
    static let iconsetEntries: [(name: String, pixels: Int)] = [16, 32, 128, 256, 512].flatMap { points in
        [("icon_\(points)x\(points).png", points), ("icon_\(points)x\(points)@2x.png", points * 2)]
    }

    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in iconsetEntries {
            try writePNG(image(pixels: entry.pixels), to: folder.appending(path: entry.name, directoryHint: .notDirectory))
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    // MARK: Drawing

    /// The icon at `pixels` square, drawn in reference coordinates and scaled.
    static func image(pixels: Int) -> CGImage {
        image(pixels: pixels, look: look(forPixels: pixels))
    }

    static func image(pixels: Int, look: Look) -> CGImage {
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        let scale = CGFloat(pixels) / canvas
        context.scaleBy(x: scale, y: scale)
        draw(in: context, scale: scale, look: look)
        return context.makeImage()!
    }

    /// Draws the icon in reference coordinates (y up). `scale` is device pixels per reference pixel.
    static func draw(in context: CGContext, scale: CGFloat, look: Look) {
        let rect = CGRect(x: (canvas - bodySide) / 2, y: (canvas - bodySide) / 2, width: bodySide, height: bodySide)
        let body = RoundedRectangle(cornerRadius: bodyCornerRadius, style: .continuous).path(in: rect).cgPath

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -shadowOffset * scale), blur: shadowBlur * scale, color: CGColor(gray: 0, alpha: shadowAlpha))
        context.addPath(body)
        context.setFillColor(bodyBottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(body)
        context.clip()
        drawLinearGradient(in: context, colors: [bodyTop.cgColor, bodyBottom.cgColor], from: rect.maxY, to: rect.minY)
        drawGlow(in: context, look: look)
        drawFace(in: context, look: look)
        if look.highlight {
            drawHighlight(in: context, body: body, rect: rect, scale: scale)
        }
        context.restoreGState()
    }

    /// One face, the way `BlobLayerTree` builds it: the body path filled with the colour, the two
    /// eye capsules in `Theme.blobEyeColor` clipped to the body.
    static func drawFace(in context: CGContext, look: Look) {
        let size = look.faceSize
        context.saveGState()
        context.translateBy(x: look.faceCentre.x - size / 2, y: look.faceCentre.y - size / 2)
        let silhouette = look.body.profile.path(size: size)
        context.addPath(silhouette)
        context.setFillColor(look.color.cgColor)
        context.fillPath()
        context.addPath(silhouette)
        context.clip()
        context.setFillColor(Theme.blobEyeColor.cgColor)
        for mirrored in [false, true] {
            context.addPath(BlobEyes.path(for: look.pose, body: look.body, faceSize: size, mirrored: mirrored))
        }
        context.fillPath()
        context.restoreGState()
    }

    /// A radial glow of the face colour behind the face, like the done halo in the panel.
    static func drawGlow(in context: CGContext, look: Look) {
        guard look.glowAlpha > 0 else { return }
        let colors = [look.color.cgColor.copy(alpha: look.glowAlpha)!, look.color.cgColor.copy(alpha: 0)!]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: look.faceCentre, startRadius: 0, endCenter: look.faceCentre, endRadius: look.glowRadius, options: [])
    }

    /// The faint inner highlight: the outline's inner band, white fading out toward the middle.
    static func drawHighlight(in context: CGContext, body: CGPath, rect: CGRect, scale: CGFloat) {
        let width = max(highlightWidth, 1 / scale)
        context.saveGState()
        context.addPath(body.copy(strokingWithWidth: width * 2, lineCap: .butt, lineJoin: .round, miterLimit: 1))
        context.clip()
        drawLinearGradient(in: context, colors: [CGColor(gray: 1, alpha: highlightAlpha), CGColor(gray: 1, alpha: 0)], from: rect.maxY, to: rect.maxY - rect.height * highlightReach)
        context.restoreGState()
    }

    /// A vertical gradient over the current clip, from `from` (y) to `to`.
    private static func drawLinearGradient(in context: CGContext, colors: [CGColor], from: CGFloat, to: CGFloat) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to), options: [])
    }
}
