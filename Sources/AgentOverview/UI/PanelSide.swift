import QuartzCore
import SwiftUI

/// The screen edge the panel docks to (Settings > General > Panel side, `panelSide`).
///
/// The panel's horizontal geometry is written once, for the right edge: the canonical side, where the
/// screen edge is at the content's maximum x and everything grows toward smaller x. On the left the
/// same geometry is drawn mirrored, through the few helpers here: `mirror(x:in:)` for a coordinate,
/// `mirror(dx:)` for an offset or a velocity, `mirror(_:in:)` for a rect or a path and `transform(in:)`
/// for a drawing context. Each mirror is its own inverse, so one call maps a canonical value onto this
/// side and a value on this side back to canonical. On the right every helper is the identity.
///
/// What is mirrored where: the window frame (`PanelPlacement`), the hosting view's anchor in the
/// window (`PanelWindow`), the row order (face, then bulge), the bulge texts' alignment, the goo
/// (both renderers draw the canonical shape through `transform(in:)`), `CapsuleShape`, the edge cue
/// (`AttentionEdgeLayout`), the pointer's distance from the edge (`PanelModel`), the press axis and
/// the throw (`PressAxis`, `FaceThrow`) and the faces themselves (`faceTransform`: gaze, genie
/// stretch and halo face the screen). The magnification needs nothing: it works on the real pointer.
enum PanelSide: String, CaseIterable, Sendable {
    case right
    case left

    /// The `Theme` default: the right edge.
    static let `default` = PanelSide.right

    /// Whether this side draws the canonical (right-edge) geometry mirrored.
    var isMirrored: Bool { self == .left }

    /// +1 when the screen edge lies toward +x (right), -1 when it lies toward -x (left).
    var outward: CGFloat { isMirrored ? -1 : 1 }

    /// A horizontal offset, velocity or travel mirrored for this side (negated on the left).
    func mirror(dx: CGFloat) -> CGFloat { dx * outward }

    /// An x coordinate in a span `0 ... width` mirrored for this side (`width - x` on the left).
    func mirror(x: CGFloat, in width: CGFloat) -> CGFloat { isMirrored ? width - x : x }

    /// A rect in a span `0 ... width` mirrored for this side.
    func mirror(_ rect: CGRect, in width: CGFloat) -> CGRect {
        guard isMirrored else { return rect }
        return CGRect(x: width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// A path in a span `0 ... width` mirrored for this side.
    func mirror(_ path: Path, in width: CGFloat) -> Path {
        isMirrored ? path.applying(transform(in: width)) : path
    }

    /// The affine transform that mirrors the span `0 ... width` for this side (identity on the right).
    /// A rect's own span is `rect.minX + rect.maxX` wide from 0, so `transform(in: rect.minX + rect.maxX)`
    /// mirrors a drawing about the rect's centre.
    func transform(in width: CGFloat) -> CGAffineTransform {
        isMirrored ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0) : .identity
    }

    /// How far `x` lies from the screen edge in a view `width` wide whose edge is this side.
    func distanceFromEdge(x: CGFloat, width: CGFloat) -> CGFloat {
        isMirrored ? x : width - x
    }

    /// The x that lies `distance` from the screen edge in a view `width` wide.
    func x(fromEdge distance: CGFloat, width: CGFloat) -> CGFloat {
        mirror(x: width - distance, in: width)
    }

    /// The SwiftUI alignment of the screen edge (trailing on the right, leading on the left).
    var edgeAlignment: Alignment { isMirrored ? .leading : .trailing }

    /// The sublayer transform that mirrors a face square about its centre on the left (identity on
    /// the right), so a face looks and stretches toward the screen, not into the edge. Set as a
    /// sublayer transform on a centred layer, it flips about the layer's anchor (its centre).
    var faceTransform: CATransform3D {
        isMirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    /// Label in Settings.
    var title: String {
        switch self {
        case .right: "Right"
        case .left: "Left"
        }
    }

    /// The order the Settings picker shows them in, left to right as on the screen.
    static let settingsChoices: [PanelSide] = [.left, .right]
}
