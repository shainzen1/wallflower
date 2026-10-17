import AppKit
import ImageIO
import QuartzCore
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures one of the app's own windows to a PNG (`--snapshot`), for scripted screenshot reviews
/// on a machine where no process holds Screen Recording permission.
///
/// `.layer` (default) renders the window's Core Animation presentation tree in-process, so a running
/// loop is caught mid-flight. `CALayer.render(in:)` ignores transforms (the pulse, grow and hop live on
/// `transform.scale`) and the root's own flip, so the tree is walked here: every layer's position,
/// anchor, affine transform, opacity, flip and shape mask are applied by hand, shape layers are filled
/// directly and only leaf layers (SwiftUI text, the goo canvas) go through `render(in:)`.
/// `.view` lets AppKit draw the window's views itself (`cacheDisplay(in:to:)` on the frame view, so the
/// titlebar and the toolbar come along): the method for windows of standard controls (Settings, the
/// welcome), which the layer walk does not know how to draw. Faces in such a window are hidden for
/// AppKit's pass (it misplaces transformed layers) and drawn on top by the layer walk.
/// `.screenCaptureKit` asks the window server instead (needs the app to hold Screen Recording).
/// What lies behind the window is never captured; the image is composited over `backgroundGray`.
@MainActor
enum WindowSnapshot {
    /// Flat background behind the transparent parts of the window (a dark desktop).
    static let backgroundGray: CGFloat = 0.16

    enum Method: String { case layer, view, screenCaptureKit }

    /// `--snapshot-grow <seconds>`: render the waiting faces with the attention grow evaluated at this
    /// time into its interval, from the loop's definition (the presentation tree does not expose
    /// transform animations, so the grow cannot be caught live by `.layer`).
    static var growTime: TimeInterval?

    /// The grow loop's scale at `time` (0 at rest): ease-out up, ease-in-out down, still afterwards.
    static func growScale(at time: TimeInterval) -> Double {
        let grow = Theme.attentionGrow
        let t = time.truncatingRemainder(dividingBy: grow.interval)
        let up = grow.duration * grow.upFraction
        let delta = grow.scale - 1
        if t < up {
            return 1 + delta * bezier(t / up, 0.16, 1, 0.3, 1)
        }
        if t < grow.duration {
            return 1 + delta * (1 - bezier((t - up) / (grow.duration - up), 0.42, 0, 0.58, 1))
        }
        return 1
    }

    /// y of a CSS/Core Animation cubic timing curve at progress `x`, solved by bisection.
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func point(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if point(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return point((low + high) / 2, y1, y2)
    }

    static func capture(_ window: NSWindow, to url: URL, scale: CGFloat, method: Method) async throws {
        switch method {
        case .layer: try renderLayers(of: window, to: url, scale: scale)
        case .view: try renderViews(of: window, to: url, scale: scale)
        case .screenCaptureKit: try await captureWithScreenCaptureKit(window, to: url, scale: scale)
        }
    }

    // MARK: Layer walk

    private static func renderLayers(of window: NSWindow, to url: URL, scale: CGFloat) throws {
        guard let view = window.contentView, let layer = view.layer else { throw SnapshotError.windowNotListed }
        let size = view.bounds.size
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotError.contextFailed }
        context.setFillColor(gray: backgroundGray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // The root is drawn in its own bounds; its position is the window's, not applied.
        drawContents(of: layer.presentation() ?? layer, in: context)
        guard let image = context.makeImage() else { throw SnapshotError.contextFailed }
        try writePNG(image, to: url)
    }

    /// Draws `layer` (geometry applied) and its subtree.
    private static func draw(_ layer: CALayer, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0 else { return }
        context.saveGState()
        applyGeometry(of: layer, to: context)
        let opacity = CGFloat(layer.opacity)
        if opacity < 1 {
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        drawContents(of: layer, in: context)
        if opacity < 1 {
            context.endTransparencyLayer()
        }
        context.restoreGState()
    }

    /// The layer's own content and its sublayers, in the layer's bounds coordinate space.
    private static func drawContents(of layer: CALayer, in context: CGContext) {
        if layer.masksToBounds {
            context.clip(to: layer.bounds)
        }
        if let mask = layer.mask {
            clip(context, to: mask)
        }
        let sublayers = layer.sublayers ?? []
        // SwiftUI's drawing layers (the goo canvas) keep their surface in a zero-sized image queue
        // sublayer; such a layer is a leaf for `render(in:)`, which knows how to draw it.
        let isDrawingLeaf = layer.contents == nil && !sublayers.isEmpty && sublayers.allSatisfy { $0.bounds.isEmpty }
        if layer.shadowOpacity > 0, let shadowPath = layer.shadowPath, let shadowColor = layer.shadowColor {
            drawShadow(of: shadowPath, color: shadowColor.copy(alpha: shadowColor.alpha * CGFloat(layer.shadowOpacity)) ?? shadowColor, radius: layer.shadowRadius, offset: layer.shadowOffset, in: context)
        }
        if let shape = layer as? CAShapeLayer {
            if let path = shape.path, let fill = shape.fillColor {
                context.addPath(path)
                context.setFillColor(fill)
                context.fillPath(using: shape.fillRule == .evenOdd ? .evenOdd : .winding)
            }
        } else if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            drawImage(contents as! CGImage, of: layer, in: context)
        } else if sublayers.isEmpty || isDrawingLeaf {
            layer.render(in: context)
        }
        guard !sublayers.isEmpty, !isDrawingLeaf else { return }
        context.saveGState()
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: layer.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        // The sublayer transform (a departing or thrown face), about the anchor point like Core Animation.
        let sublayerTransform = layer.sublayerTransform
        if !CATransform3DIsIdentity(sublayerTransform), CATransform3DIsAffine(sublayerTransform) {
            let bounds = layer.bounds
            let anchor = CGPoint(x: bounds.minX + bounds.width * layer.anchorPoint.x, y: bounds.minY + bounds.height * layer.anchorPoint.y)
            context.translateBy(x: anchor.x, y: anchor.y)
            context.concatenate(CATransform3DGetAffineTransform(sublayerTransform))
            context.translateBy(x: -anchor.x, y: -anchor.y)
        }
        for sublayer in sublayers {
            draw(sublayer, in: context)
        }
        context.restoreGState()
    }

    /// A layer's shadow from its `shadowPath` (the halo, the dot-matrix glow), beneath its content: the
    /// path is filled far outside the visible area with the shadow offset back onto it, so only the
    /// shadow lands. Core Animation's `shadowRadius` is the Gaussian sigma, Core Graphics' blur is twice
    /// the sigma (both measured), and both the blur and the offset of `setShadow` are in device space.
    private static func drawShadow(of path: CGPath, color: CGColor, radius: CGFloat, offset: CGSize, in context: CGContext) {
        let ctm = context.ctm
        let deviceScale = abs(ctm.a * ctm.d - ctm.b * ctm.c).squareRoot()
        let box = path.boundingBoxOfPath
        let away = box.maxX + box.width + radius * 8 + 1000
        let deviceAway = CGSize(width: ctm.a * away, height: ctm.b * away)
        let deviceOffset = CGSize(width: ctm.a * offset.width + ctm.c * offset.height, height: ctm.b * offset.width + ctm.d * offset.height)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: deviceOffset.width - deviceAway.width, height: deviceOffset.height - deviceAway.height),
            blur: 2 * radius * deviceScale, color: color
        )
        context.translateBy(x: away, y: 0)
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
        context.restoreGState()
    }

    /// Position, anchor point and affine transform, so the layer's bounds origin is the context origin.
    private static func applyGeometry(of layer: CALayer, to context: CGContext) {
        if let time = growTime, (layer.model().animationKeys() ?? []).contains("loop.grow") {
            // A rendered frame of the grow loop at `time`: the loop's own curve, not a capture.
            let factor = CGFloat(growScale(at: time))
            let bounds = layer.bounds
            let anchor = CGPoint(x: bounds.midX, y: bounds.midY)
            context.translateBy(x: layer.position.x, y: layer.position.y)
            context.concatenate(layer.model().affineTransform())
            context.scaleBy(x: factor, y: factor)
            context.translateBy(x: -anchor.x, y: -anchor.y)
            return
        }
        let bounds = layer.bounds
        let anchor = CGPoint(x: bounds.minX + bounds.width * layer.anchorPoint.x, y: bounds.minY + bounds.height * layer.anchorPoint.y)
        context.translateBy(x: layer.position.x, y: layer.position.y)
        context.concatenate(layer.affineTransform())
        context.translateBy(x: -anchor.x, y: -anchor.y)
    }

    /// Clips to a shape mask (its own geometry applied); image masks are skipped.
    private static func clip(_ context: CGContext, to mask: CALayer) {
        guard let shape = mask as? CAShapeLayer, let path = shape.path else { return }
        context.saveGState()
        applyGeometry(of: shape, to: context)
        context.addPath(path)
        context.restoreGState()
        context.clip()
    }

    private static func drawImage(_ image: CGImage, of layer: CALayer, in context: CGContext) {
        context.saveGState()
        if layer.contentsAreFlipped() {
            context.translateBy(x: 0, y: layer.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: layer.bounds)
        context.restoreGState()
    }

    // MARK: AppKit drawing

    /// The whole window as AppKit draws it (frame view: titlebar, toolbar, content), over the window's
    /// own background colour, at `scale` pixels per point.
    private static func renderViews(of window: NSWindow, to url: URL, scale: CGFloat) throws {
        guard let frameView = window.contentView?.superview ?? window.contentView else { throw SnapshotError.windowNotListed }
        frameView.layoutSubtreeIfNeeded()
        let bounds = frameView.bounds
        let faces = faceViews(in: frameView)
        let wasHidden = faces.map(\.isHidden)
        faces.forEach { $0.isHidden = true }
        defer { zip(faces, wasHidden).forEach { $0.isHidden = $1 } }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw SnapshotError.contextFailed }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        guard let drawn = rep.cgImage else { throw SnapshotError.contextFailed }
        guard let context = CGContext(
            data: nil, width: drawn.width, height: drawn.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotError.contextFailed }
        var background = window.backgroundColor.cgColor
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = window.backgroundColor.cgColor
        }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
        context.draw(drawn, in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
        context.scaleBy(x: scale, y: scale)
        for (face, hidden) in zip(faces, wasHidden) where !hidden && face.window != nil && face.alphaValue > 0 {
            guard let layer = face.layer else { continue }
            var frame = face.convert(face.bounds, to: frameView)
            if frameView.isFlipped { frame.origin.y = bounds.height - frame.maxY }
            context.saveGState()
            context.translateBy(x: frame.minX, y: frame.minY)
            if face.isFlipped, !layer.isGeometryFlipped {
                context.translateBy(x: 0, y: frame.height)
                context.scaleBy(x: 1, y: -1)
            }
            drawContents(of: layer.presentation() ?? layer, in: context)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw SnapshotError.contextFailed }
        try writePNG(image, to: url)
    }

    /// The face host views under `view` (blob and dot-matrix eyes), whose layer trees the walk draws.
    private static func faceViews(in view: NSView) -> [NSView] {
        var found: [NSView] = []
        for subview in view.subviews {
            if subview is BlobHostView || subview is EyesHostView {
                found.append(subview)
            } else {
                found += faceViews(in: subview)
            }
        }
        return found
    }

    // MARK: Menu bar glyph

    /// Writes the status item glyphs for review, next to `url`: each state at 1x and 2x as the template
    /// (`<name>-calm@1x.png` ...), and `<name>-sheet.png`, every rendering on a light and a dark menu bar
    /// tint, enlarged 8 times without smoothing so each pixel shows, plus the menu's status shapes.
    static func writeMenuBarGlyphs(to url: URL) throws -> [URL] {
        let base = url.deletingPathExtension()
        var written: [URL] = []
        let glyphs: [(name: String, glyph: MenuBarIcon.Glyph)] = [("calm", .calm), ("needsyou", .needsYou)]
        for (name, glyph) in glyphs {
            for scale in [1, 2] {
                let image = try glyphImage(MenuBarIcon.size, scale: CGFloat(scale), ink: .black, paper: nil) { MenuBarIcon.path(glyph, in: $0) }
                let file = URL(filePath: base.path + "-\(name)@\(scale)x.png")
                try writePNG(image, to: file)
                written.append(file)
            }
        }

        // Contact sheet: rows = light and dark bar; columns = calm 1x, calm 2x, needs you 1x, needs you 2x,
        // then the three status shapes of the menu items at 2x.
        let magnify = 8
        let cell = 18 * 2 * magnify + 16
        let shapes: [FaceStatus] = [.needsInput(kind: .question), .working, .idle(since: Date())]
        let columns = glyphs.count * 2 + shapes.count
        let bars: [(paper: CGColor, ink: CGColor)] = [
            (CGColor(gray: 0.93, alpha: 1), CGColor(gray: 0, alpha: 0.85)),
            (CGColor(gray: 0.13, alpha: 1), CGColor(gray: 1, alpha: 1)),
        ]
        guard let sheet = CGContext(
            data: nil, width: cell * columns, height: cell * bars.count, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotError.contextFailed }
        sheet.interpolationQuality = .none
        for (row, bar) in bars.enumerated() {
            let y = (bars.count - 1 - row) * cell
            sheet.setFillColor(bar.paper)
            sheet.fill(CGRect(x: 0, y: y, width: cell * columns, height: cell))
            var column = 0
            for (_, glyph) in glyphs {
                for scale in [1, 2] {
                    let image = try glyphImage(MenuBarIcon.size, scale: CGFloat(scale), ink: bar.ink, paper: bar.paper) { MenuBarIcon.path(glyph, in: $0) }
                    let side = image.width * magnify * (2 / scale)
                    sheet.draw(image, in: CGRect(x: column * cell + (cell - side) / 2, y: y + (cell - side) / 2, width: side, height: side))
                    column += 1
                }
            }
            for status in shapes {
                let shape = BlobBody.forStatus(status).shape
                let image = try glyphImage(NSSize(width: 16, height: 16), scale: 2, ink: bar.ink, paper: bar.paper) {
                    MenuBarIcon.path(shape: shape, in: $0, extent: 14)
                }
                let side = image.width * magnify
                sheet.draw(image, in: CGRect(x: column * cell + (cell - side) / 2, y: y + (cell - side) / 2, width: side, height: side))
                column += 1
            }
        }
        guard let sheetImage = sheet.makeImage() else { throw SnapshotError.contextFailed }
        let sheetURL = URL(filePath: base.path + "-sheet.png")
        try writePNG(sheetImage, to: sheetURL)
        written.append(sheetURL)
        return written
    }

    /// A glyph path filled even-odd at `scale` pixels per point, in `ink` over `paper` (transparent when nil).
    private static func glyphImage(_ size: NSSize, scale: CGFloat, ink: CGColor, paper: CGColor?, path: (CGRect) -> CGPath) throws -> CGImage {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotError.contextFailed }
        if let paper {
            context.setFillColor(paper)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.scaleBy(x: scale, y: scale)
        context.addPath(path(CGRect(origin: .zero, size: size)))
        context.setFillColor(ink)
        context.fillPath(using: .evenOdd)
        guard let image = context.makeImage() else { throw SnapshotError.contextFailed }
        return image
    }

    // MARK: ScreenCaptureKit

    private static func captureWithScreenCaptureKit(_ window: NSWindow, to url: URL, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw SnapshotError.windowNotListed
        }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(target.frame.width * scale)
        configuration.height = Int(target.frame.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try composite(image, to: url)
    }

    /// Composites the capture over the flat background and writes the PNG.
    private static func composite(_ image: CGImage, to url: URL) throws {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotError.contextFailed }
        context.setFillColor(gray: backgroundGray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let composed = context.makeImage() else { throw SnapshotError.contextFailed }
        try writePNG(composed, to: url)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SnapshotError.contextFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.writeFailed }
    }

    enum SnapshotError: Error {
        case windowNotListed, contextFailed, writeFailed
    }
}
