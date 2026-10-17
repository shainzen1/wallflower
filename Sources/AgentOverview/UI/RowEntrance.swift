import SwiftUI

/// A spring in SwiftUI's terms (response and bounce), with the physics Core Animation needs
/// (`CASpringAnimation` mass, stiffness, damping) and the moments the entrance hangs off it:
/// when it first reaches its target (the landing) and when its swing has died down (settled).
/// Unit mass; `bounce` in 0..<1 (underdamped), damping ratio `1 - bounce` as in SwiftUI.
struct EntranceSpring: Equatable, Sendable {
    var response: TimeInterval
    var bounce: Double

    var mass: Double { 1 }
    /// Undamped angular frequency.
    var omega: Double { 2 * .pi / response }
    var dampingRatio: Double { 1 - bounce }
    var stiffness: Double { omega * omega * mass }
    var damping: Double { 2 * dampingRatio * omega * mass }
    /// Decay rate of the envelope.
    private var decay: Double { dampingRatio * omega }
    /// Damped angular frequency.
    private var dampedOmega: Double { omega * (1 - dampingRatio * dampingRatio).squareRoot() }

    /// Progress from 0 (start) to 1 (target) at `time`, starting at rest; above 1 while it overshoots.
    func progress(at time: TimeInterval) -> Double {
        guard time > 0 else { return 0 }
        let wd = dampedOmega
        return 1 - exp(-decay * time) * (cos(wd * time) + decay / wd * sin(wd * time))
    }

    /// The first time the spring reaches its target (it then overshoots): the landing.
    var landingTime: TimeInterval {
        (.pi - atan(dampedOmega / decay)) / dampedOmega
    }

    /// The top of the overshoot, as a fraction of the travel.
    var overshoot: Double {
        exp(-decay * .pi / dampedOmega)
    }

    /// When the swing left (the envelope) stays below `tolerance` of the travel.
    func settleTime(tolerance: Double) -> TimeInterval {
        let amplitude = 1 / (1 - dampingRatio * dampingRatio).squareRoot()
        return max(log(amplitude / tolerance) / decay, 0)
    }

    /// The same spring as a SwiftUI animation.
    var animation: Animation {
        .spring(response: response, dampingFraction: dampingRatio)
    }
}

/// The arrival and departure of a row, as pure timing (tested) plus the SwiftUI pieces that use it.
///
/// Arrival: the slot opens first (`Theme.rowOpenDuration`, ease-out; the neighbours slide apart, the
/// capsule body grows in step), then the face pops in its own layer tree: `faceDelay` after the
/// insertion it scales from `Theme.rowEnterScale` on `Theme.rowEnterSpring` and fades in, lands
/// with the hop's tiny squash, and opens its lids once the spring settled. Several rows arriving in
/// one change pop staggered top to bottom. Departure: the face shrinks and fades (SwiftUI, the view
/// is going away), then the slot closes. Reduce Motion: fades only, slots open and close at once.
enum RowEntrance {
    // MARK: Face timing (the pop, in the face's layer tree)

    /// Seconds from the row's insertion to the face's pop: after the slot opened (less the overlap)
    /// when a slot opens, plus the stagger step of its `order` among the rows arriving together.
    static func faceDelay(order: Int, slotOpens: Bool, reduceMotion: Bool) -> TimeInterval {
        let stagger = Double(min(max(order, 0), Theme.rowEnterStaggerCap)) * Theme.rowEnterStagger
        guard slotOpens, !reduceMotion else { return stagger }
        return max(Theme.rowOpenDuration - Theme.rowEnterOverlap, 0) + stagger
    }

    /// The face delays of the rows that are new in `current` (stack ids, top to bottom) compared to
    /// `previous`, keyed by id. `previous` nil is the first layout: no slot opens (the stack is
    /// there from the start), the faces only stagger in. Non-face ids (the divider) take no step.
    static func faceDelays(previous: [String]?, current: [String], reduceMotion: Bool, isFace: (String) -> Bool = { $0 != "divider" }) -> [String: TimeInterval] {
        let known = Set(previous ?? [])
        let arriving = current.filter { isFace($0) && !known.contains($0) }
        var delays: [String: TimeInterval] = [:]
        for (order, id) in arriving.enumerated() {
            delays[id] = faceDelay(order: order, slotOpens: previous != nil, reduceMotion: reduceMotion)
        }
        return delays
    }

    /// The moments of one face's pop, in seconds from the moment the face is installed.
    struct FaceTiming: Equatable {
        /// The pop begins (the face is invisible before).
        var delay: TimeInterval
        var reduceMotion: Bool

        var spring: EntranceSpring { Theme.rowEnterSpring }
        var fromScale: Double { reduceMotion ? 1 : Double(Theme.rowEnterScale) }
        var fadeDuration: TimeInterval { reduceMotion ? Theme.reduceMotionFadeDuration : Theme.rowEnterFadeDuration }
        /// The landing squash starts (the spring first reaches full size).
        var landing: TimeInterval { delay + spring.landingTime }
        /// The squash is released.
        var landingEnd: TimeInterval { landing + Theme.hopSquashDuration }
        /// The lids start to open (the spring settled). Under Reduce Motion the eyes are open from the start.
        var eyesOpen: TimeInterval { reduceMotion ? delay : delay + spring.settleTime(tolerance: Theme.rowEnterSettleTolerance) }
        /// The lids are open; the face's loops begin here.
        var end: TimeInterval { reduceMotion ? delay + fadeDuration : eyesOpen + Theme.blobBlinkOpen }
    }

    // MARK: Slot (SwiftUI)

    /// The slot opening: ease-out over `Theme.rowOpenDuration`; nil (at once) under Reduce Motion.
    static func slotOpenAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: Theme.rowOpenDuration)
    }

    /// The capsule body closing in step with a departing slot: still while the face leaves, then
    /// `departure(...).slot`'s curve (`SlotCloseCurve`). Not `.delay`: measured, SwiftUI dropped the
    /// delay of an `.animation(_:value:)` here and the body shrank while the face was still fading.
    static func slotCloseAnimation(reduceMotion: Bool) -> Animation {
        Animation(SlotCloseCurve(reduceMotion: reduceMotion))
    }

    /// Under Reduce Motion a slot closes in this long (a snap: SwiftUI needs a duration to delay).
    static let reduceMotionSnap: TimeInterval = 0.001

    /// When a departing row is gone for good (face out, slot closed), from its removal.
    static func departureEnd(reduceMotion: Bool) -> TimeInterval {
        Theme.rowLeaveDuration + (reduceMotion ? reduceMotionSnap : Theme.rowCloseDuration)
    }

    /// The one curve of a departure: linear over `departureEnd`, so `RowDeparture` can map its
    /// progress onto the two phases. Also the stack's animation when it shrinks (`PanelModel.layoutAnimation`).
    static func departureAnimation(reduceMotion: Bool) -> Animation {
        .linear(duration: departureEnd(reduceMotion: reduceMotion))
    }

    /// What a departing row shows `elapsed` seconds after its removal: the face's scale (ease-in-out
    /// to `Theme.rowExitScale` over `Theme.rowLeaveDuration`) and opacity (ease-out to 0 over the
    /// same), then the slot's open fraction (ease-in-out to 0 over `Theme.rowCloseDuration`).
    /// Reduce Motion: no scale, the slot snaps shut once the fade is over.
    static func departure(elapsed: TimeInterval, reduceMotion: Bool) -> (scale: Double, opacity: Double, slot: Double) {
        let leave = min(max(elapsed / Theme.rowLeaveDuration, 0), 1)
        let opacity = 1 - easeOut(leave)
        if reduceMotion {
            return (1, opacity, elapsed >= Theme.rowLeaveDuration ? 0 : 1)
        }
        let close = min(max((elapsed - Theme.rowLeaveDuration) / Theme.rowCloseDuration, 0), 1)
        let scale = 1 - (1 - Double(Theme.rowExitScale)) * easeInOut(leave)
        return (scale, opacity, 1 - easeInOut(close))
    }

    /// SwiftUI's own ease-out and ease-in-out on 0...1, so the slot closes on exactly the curve the
    /// capsule body animates with (`slotCloseAnimation`).
    static func easeOut(_ x: Double) -> Double { UnitCurve.easeOut.value(at: x) }
    static func easeInOut(_ x: Double) -> Double { UnitCurve.easeInOut.value(at: x) }

    /// The transition of one stack item `height` tall (a row, or the divider with `scales` false).
    /// Insertion: the slot opens (the face pops in its own layer tree). Removal: one linear progress
    /// over `departureEnd` that `RowDeparture` maps onto both phases (face out, then slot shut).
    /// Two measured pitfalls shape this: a combined removal runs every part on the outermost part's
    /// animation (a delayed slot close ran undelayed, the rows closed in on a face still showing),
    /// and scale and opacity set per frame by a SwiftUI modifier never reach the AppKit-hosted face.
    /// So the face's share travels as `FaceLeave` through the environment to its host layer.
    /// Reduce Motion: the slot is simply there on insertion, the removal only fades.
    static func transition(height: CGFloat, scales: Bool = true, reduceMotion: Bool) -> AnyTransition {
        let removal = AnyTransition.modifier(
            active: RowDeparture(height: height, scales: scales, reduceMotion: reduceMotion, progress: 1),
            identity: RowDeparture(height: height, scales: scales, reduceMotion: reduceMotion, progress: 0)
        ).animation(departureAnimation(reduceMotion: reduceMotion))
        if reduceMotion {
            return .asymmetric(insertion: .identity, removal: removal)
        }
        let open = AnyTransition.modifier(active: RowSlot(height: height, fraction: 0), identity: RowSlot(height: height, fraction: 1))
        return .asymmetric(insertion: open.animation(slotOpenAnimation(reduceMotion: false)), removal: removal)
    }
}

/// The capsule body's share of a departure as a SwiftUI animation: the fraction of the change done
/// at `time` is `1 - RowEntrance.departure(elapsed: time).slot`, so the body holds while the face
/// fades and then closes on exactly the slot's curve.
struct SlotCloseCurve: CustomAnimation {
    let reduceMotion: Bool

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < RowEntrance.departureEnd(reduceMotion: reduceMotion) else { return nil }
        return value.scaled(by: 1 - RowEntrance.departure(elapsed: time, reduceMotion: reduceMotion).slot)
    }
}

/// One slot of the row stack: `height` times `fraction` tall, its content centred (and overflowing
/// while the slot is not fully open). Animatable, so the neighbours follow it frame by frame.
struct RowSlot: ViewModifier, Animatable {
    let height: CGFloat
    var fraction: CGFloat

    nonisolated var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(height: max(height * fraction, 0))
    }
}

/// A departing stack item, `progress` from 0 (present) to 1 (gone) over `RowEntrance.departureEnd`:
/// the face shrinks and fades (handed to the face as `FaceLeave`; a stack item without a face, the
/// divider, fades as a SwiftUI view), then the slot closes (`RowEntrance.departure`).
struct RowDeparture: ViewModifier, Animatable {
    let height: CGFloat
    /// A row with a face (shrinks and fades through `FaceLeave`); false for the divider (fades only).
    let scales: Bool
    let reduceMotion: Bool
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let elapsed = progress * RowEntrance.departureEnd(reduceMotion: reduceMotion)
        let state = RowEntrance.departure(elapsed: elapsed, reduceMotion: reduceMotion)
        content
            .environment(\.faceLeave, scales ? FaceLeave(scale: state.scale, opacity: state.opacity) : .none)
            .opacity(scales ? 1 : state.opacity)
            .frame(height: max(height * state.slot, 0))
    }
}

/// How far a face has left (`RowDeparture`): its scale about its own centre and its opacity, both 1
/// while it is not leaving. Applied straight to the face's host layer, frame by frame, no animation.
struct FaceLeave: Equatable, Sendable {
    var scale: Double
    var opacity: Double

    static let none = FaceLeave(scale: 1, opacity: 1)

    /// Sets the leave on a face host's root layer: a scale about the bounds' centre on the sublayer
    /// transform (the anchor of an AppKit view's layer may sit at its corner) and the opacity on the
    /// top-level sublayers (the root's own opacity belongs to AppKit). Nothing changes while `.none`
    /// stays `.none`.
    @MainActor
    func apply(to root: CALayer) {
        let sublayers = root.sublayers ?? []
        let opacity = Float(self.opacity)
        let pivotX = root.bounds.width * (0.5 - root.anchorPoint.x)
        let pivotY = root.bounds.height * (0.5 - root.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(pivotX, pivotY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -pivotX, -pivotY, 0)
        let target = self == .none ? CATransform3DIdentity : transform
        guard !CATransform3DEqualToTransform(root.sublayerTransform, target) || sublayers.contains(where: { $0.opacity != opacity }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.sublayerTransform = target
        for layer in sublayers { layer.opacity = opacity }
        CATransaction.commit()
    }
}

/// Environment key of `FaceLeave` (a plain key: the Command Line Tools ship no SwiftUI macros, so no `@Entry`).
private struct FaceLeaveKey: EnvironmentKey {
    static let defaultValue = FaceLeave.none
}

extension EnvironmentValues {
    /// The leave of the faces in this subtree (`RowDeparture` sets it on a departing row).
    var faceLeave: FaceLeave {
        get { self[FaceLeaveKey.self] }
        set { self[FaceLeaveKey.self] = newValue }
    }
}
