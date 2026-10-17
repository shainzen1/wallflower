import AppKit

/// The status item's glyph, drawn in code as an 18 x 18 pt template image: a blob face silhouette
/// with two eye cut-outs, built from the faces' own geometry (`BlobShape` profiles, the eye placement
/// of `BlobEyes`). At rest it is the idle capsule with calm eyes; while a session needs input it
/// becomes the drop with the wide eyes of a waiting face, so the menu bar carries the panel's signal.
/// The flat edges and the eyes sit on whole points, so the glyph is crisp at 1x as well as 2x.
enum MenuBarIcon {
    enum Glyph: Equatable, CaseIterable {
        /// No session needs the person: the idle capsule.
        case calm
        /// At least one session needs input: the drop.
        case needsYou

        var shape: BlobShape {
            switch self {
            case .calm: Theme.blobIdleShape
            case .needsYou: Theme.blobNeedsInputShape
            }
        }

        /// The eyes: calm, or the wide look of a waiting face.
        var expression: Expression {
            switch self {
            case .calm: .normal
            case .needsYou: .surprised
            }
        }

        /// Eye cut-outs relative to the face's own eyes: the calm eyes need to be bolder to read at
        /// this size; the wide eyes already are, and the drop needs body left around them.
        var eyeScale: Double {
            switch self {
            case .calm: 1.2
            case .needsYou: 1.0
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .calm: AppInfo.name
            case .needsYou: "\(AppInfo.name), a session needs you"
            }
        }
    }

    /// Size of the template image in points.
    static let size = NSSize(width: 18, height: 18)
    /// Longest side of the silhouette inside the image, in points.
    static let bodyExtent: CGFloat = 16

    static func image(_ glyph: Glyph) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(glyph, in: rect))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = glyph.accessibilityDescription
        return image
    }

    /// The glyph's outline in `rect` (y up): the body and the two eyes, to be filled even-odd so the
    /// eyes are holes.
    static func path(_ glyph: Glyph, in rect: CGRect) -> CGPath {
        path(shape: glyph.shape, expression: glyph.expression, eyeScale: glyph.eyeScale, in: rect, extent: bodyExtent)
    }

    /// A face of `shape` with the eyes of `expression` cut out, centred in `rect`, `extent` points on
    /// its longest side. The body's height is rounded to an even number of points so its top and bottom
    /// land on whole points; each eye is an upright capsule of whole points, placed where `BlobEyes`
    /// puts it on that body and snapped to the point grid, the right one mirroring the left.
    static func path(shape: BlobShape, expression: Expression = .normal, eyeScale: Double = 1.2, in rect: CGRect, extent: CGFloat) -> CGPath {
        let body = BlobBody(shape: shape)
        let unit: CGFloat = 100
        let bodyPath = body.profile.path(size: unit)
        let box = bodyPath.boundingBoxOfPath
        let height = max(2, (extent / max(box.width, box.height) * box.height / 2).rounded() * 2)
        let scale = height / box.height
        let centre = CGPoint(x: rect.midX.rounded(), y: rect.midY.rounded())
        let transform = CGAffineTransform(translationX: centre.x, y: centre.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        let combined = CGMutablePath()
        combined.addPath(bodyPath, transform: transform)

        let pose = BlobExpressions.pose(for: expression)
        let placement = BlobEyes.placement(for: pose, profile: body.profile, faceSize: unit, mirrored: false, lift: body.eyeLift)
        let eyeCentre = placement.centre.applying(transform)
        let eyeWidth = max(2, (pose.left.width * eyeScale * unit * scale).rounded())
        let eyeHeight = max(eyeWidth + 1, (pose.left.height * eyeScale * unit * scale).rounded())
        let left = CGRect(
            x: (eyeCentre.x - eyeWidth / 2).rounded(), y: (eyeCentre.y - eyeHeight / 2).rounded(),
            width: eyeWidth, height: eyeHeight
        )
        let right = CGRect(x: 2 * centre.x - left.maxX, y: left.minY, width: eyeWidth, height: eyeHeight)
        for eye in [left, right] {
            combined.addPath(CGPath(roundedRect: eye, cornerWidth: eyeWidth / 2, cornerHeight: eyeWidth / 2, transform: nil))
        }
        return combined
    }

    /// A session's shape for its menu item: the silhouette its face wears (drop, cloud, capsule), as a
    /// 16 pt template so the menu tints it like text.
    static func statusImage(for status: FaceStatus) -> NSImage {
        let shape = BlobBody.forStatus(status).shape
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(shape: shape, in: rect, extent: 14))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The glyph for a session list: the drop while any session needs input.
    static func glyph(needsInputCount: Int) -> Glyph {
        needsInputCount > 0 ? .needsYou : .calm
    }
}
