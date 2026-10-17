import SwiftUI

/// Everything the goo shape needs that moves, as one vector so SwiftUI interpolates it with
/// the springs. The droplets' lagging centre is animated separately (`GooView`), with its own spring.
struct GooState: Equatable, VectorArithmetic, Sendable {
    /// Height of the capsule body between the fillets (rows times pitch plus end padding).
    var bodyHeight: CGFloat
    /// `.all` expand mode: how much wider than `Theme.capsuleWidth` the whole body is right now.
    var bodyExtraWidth: CGFloat
    /// `.row` expand mode: width of the bulge blob (0 = closed); it overlaps the capsule by `Theme.bulgeOverlap`.
    var bulgeWidth: CGFloat
    /// Vertical centre of the bulge, from the top of the capsule (fillet included), already clamped
    /// into the body by the model, and at the first and last slot moved flush with its edge
    /// (`PanelModel.bulgeSpan(slot:)`); the renderers clamp it again into the live body while it
    /// springs (`GooLayout.bulgeSpan(state:height:)`).
    var bulgeCenterY: CGFloat
    /// Height of the bulge blob: a row's (`GooLayout.bulgeHeight`), or the new session button's shorter one.
    var bulgeHeight: CGFloat = GooLayout.bulgeHeight
    /// How flush the blob's top edge is with the body's top edge: 1 at the first slot, 0 elsewhere
    /// (`GooLayout.BulgeSpan.flushTop`). It springs with the centre, so while the blob slides into
    /// the first slot the edge margin, the capsule's top-left corner and the fillet between them
    /// shrink to nothing together, and grow back as it leaves.
    var bulgeTopFlush: CGFloat = 0
    /// The same at the bottom: 1 at the last slot.
    var bulgeBottomFlush: CGFloat = 0

    static let zero = GooState(bodyHeight: 0, bodyExtraWidth: 0, bulgeWidth: 0, bulgeCenterY: 0, bulgeHeight: 0)

    static func + (lhs: GooState, rhs: GooState) -> GooState {
        GooState(
            bodyHeight: lhs.bodyHeight + rhs.bodyHeight,
            bodyExtraWidth: lhs.bodyExtraWidth + rhs.bodyExtraWidth,
            bulgeWidth: lhs.bulgeWidth + rhs.bulgeWidth,
            bulgeCenterY: lhs.bulgeCenterY + rhs.bulgeCenterY,
            bulgeHeight: lhs.bulgeHeight + rhs.bulgeHeight,
            bulgeTopFlush: lhs.bulgeTopFlush + rhs.bulgeTopFlush,
            bulgeBottomFlush: lhs.bulgeBottomFlush + rhs.bulgeBottomFlush
        )
    }

    static func - (lhs: GooState, rhs: GooState) -> GooState {
        GooState(
            bodyHeight: lhs.bodyHeight - rhs.bodyHeight,
            bodyExtraWidth: lhs.bodyExtraWidth - rhs.bodyExtraWidth,
            bulgeWidth: lhs.bulgeWidth - rhs.bulgeWidth,
            bulgeCenterY: lhs.bulgeCenterY - rhs.bulgeCenterY,
            bulgeHeight: lhs.bulgeHeight - rhs.bulgeHeight,
            bulgeTopFlush: lhs.bulgeTopFlush - rhs.bulgeTopFlush,
            bulgeBottomFlush: lhs.bulgeBottomFlush - rhs.bulgeBottomFlush
        )
    }

    mutating func scale(by rhs: Double) {
        bodyHeight *= rhs
        bodyExtraWidth *= rhs
        bulgeWidth *= rhs
        bulgeCenterY *= rhs
        bulgeHeight *= rhs
        bulgeTopFlush *= rhs
        bulgeBottomFlush *= rhs
    }

    var magnitudeSquared: Double {
        Double(
            bodyHeight * bodyHeight + bodyExtraWidth * bodyExtraWidth + bulgeWidth * bulgeWidth
                + bulgeCenterY * bulgeCenterY + bulgeHeight * bulgeHeight
                + bulgeTopFlush * bulgeTopFlush + bulgeBottomFlush * bulgeBottomFlush
        )
    }
}
