import CoreGraphics
import Foundation

/// The capsule's column of faces as the magnification sees it: each face's centre and reach
/// (`FaceReach`), the capsule's inner ends and the divider lines. It turns the plain falloff
/// (`MagnifyState.at`, clamped to the capsule width) into states that keep every body
/// `Theme.rowBodyGap` clear of its neighbours, the divider lines and the capsule's ends.
///
/// The room between two neighbours (their centre distance less the gap) is shared: each first
/// gets what it needs at magnification 1 (its peak reach), then the rest goes to what each wants
/// (its magnified reach plus its drift toward the other); when both cannot have it, the spare room
/// is split in proportion to the wants weighted by the falloff, so the face nearer the pointer
/// gets most of it. Both faces compute the same split from the same pointer, so their shares never
/// overlap. A divider or a capsule end is not shared: the room is the distance less the gap.
/// A face that cannot magnify without crossing its room keeps scale 1 and its drift is cut short.
/// A fixed face (the new session button) never magnifies or drifts: its state is identity, it keeps
/// exactly its own reach of a shared room and the neighbour gets the rest, so the gap holds around it.
struct MagnifyColumn: Sendable {
    struct Face: Equatable, Sendable {
        /// Centre from the capsule's top (fillet included), the pointer's coordinates.
        var centerY: CGFloat
        var reach: FaceReach
        /// Never magnified: a fixed body the neighbours fit around.
        var fixed = false
    }

    var faces: [Face]
    /// Inner top and bottom edge of the capsule body, in the same coordinates.
    var top: CGFloat
    var bottom: CGFloat
    /// The divider lines (below the new session button, above the action faces), top to bottom.
    var dividers: [CGFloat] = []
    var faceSize: CGFloat = Theme.faceSize
    var gap: CGFloat = Theme.rowBodyGap

    /// The plain magnification of face `index`: the falloff, the follow, the clamp to the capsule width.
    func raw(_ index: Int, pointer: CGPoint) -> MagnifyState {
        let face = faces[index]
        guard !face.fixed else { return .identity }
        let offset = CGPoint(x: pointer.x - Theme.capsuleWidth / 2, y: pointer.y - face.centerY)
        return MagnifyState.at(
            offset: offset, distance: abs(offset.y), faceSize: faceSize,
            maxScale: MagnifyState.maxScale(faceSize: faceSize, restScale: face.reach.boxScale)
        )
    }

    /// The magnification of face `index`, fitted into its room.
    func state(_ index: Int, pointer: CGPoint) -> MagnifyState {
        guard !faces[index].fixed else { return .identity }
        return Self.fit(raw(index, pointer: pointer), reach: faces[index].reach, roomUp: roomAbove(index, pointer: pointer), roomDown: roomBelow(index, pointer: pointer))
    }

    /// Every face's magnification.
    func states(pointer: CGPoint) -> [MagnifyState] {
        faces.indices.map { state($0, pointer: pointer) }
    }

    /// How far above its centre face `index` may reach.
    func roomAbove(_ index: Int, pointer: CGPoint) -> CGFloat {
        let centre = faces[index].centerY
        guard index > 0 else { return centre - top - gap }
        let previous = faces[index - 1].centerY
        if let divider = dividers.last(where: { $0 < centre && $0 > previous }) {
            return centre - divider - gap
        }
        return share(upper: index - 1, pointer: pointer).lower
    }

    /// How far below its centre face `index` may reach.
    func roomBelow(_ index: Int, pointer: CGPoint) -> CGFloat {
        let centre = faces[index].centerY
        guard index < faces.count - 1 else { return bottom - centre - gap }
        let next = faces[index + 1].centerY
        if let divider = dividers.first(where: { $0 > centre && $0 < next }) {
            return divider - centre - gap
        }
        return share(upper: index, pointer: pointer).upper
    }

    /// The room between face `upper` and the face below it, split into the upper face's reach down
    /// and the lower face's reach up.
    func share(upper a: Int, pointer: CGPoint) -> (upper: CGFloat, lower: CGFloat) {
        let b = a + 1
        let total = faces[b].centerY - faces[a].centerY - gap
        let baseA = faces[a].reach.down
        let baseB = faces[b].reach.up
        let spare = total - baseA - baseB
        // A fixed face keeps its own reach; the room beyond it is the neighbour's.
        if faces[a].fixed { return (baseA, total - baseA) }
        if faces[b].fixed { return (total - baseB, baseB) }
        guard spare > 0 else { return (baseA + spare / 2, baseB + spare / 2) }
        let rawA = raw(a, pointer: pointer)
        let rawB = raw(b, pointer: pointer)
        let wantA = max(rawA.scale * baseA + rawA.dy - baseA, 0)
        let wantB = max(rawB.scale * baseB - rawB.dy - baseB, 0)
        if wantA + wantB <= spare {
            let left = (spare - wantA - wantB) / 2
            return (baseA + wantA + left, baseB + wantB + left)
        }
        let priorityA = wantA * MagnifyState.weight(distance: abs(pointer.y - faces[a].centerY))
        let priorityB = wantB * MagnifyState.weight(distance: abs(pointer.y - faces[b].centerY))
        let shareA = priorityA + priorityB > 0 ? spare * priorityA / (priorityA + priorityB) : spare / 2
        return (baseA + shareA, baseB + spare - shareA)
    }

    /// Fits a state into the room above and below the face: the scale shrinks until the body (with
    /// its drift) stays inside; below 1 the scale stays 1 and the drift is cut instead.
    static func fit(_ state: MagnifyState, reach: FaceReach, roomUp: CGFloat, roomDown: CGFloat) -> MagnifyState {
        var fitted = state
        let byUp = reach.up > 0 ? (roomUp + state.dy) / reach.up : .infinity
        let byDown = reach.down > 0 ? (roomDown - state.dy) / reach.down : .infinity
        fitted.scale = min(state.scale, byUp, byDown)
        if fitted.scale < 1 {
            fitted.scale = 1
            let low = reach.up - roomUp
            let high = roomDown - reach.down
            fitted.dy = low <= high ? min(max(state.dy, low), high) : (low + high) / 2
        }
        return fitted
    }
}
