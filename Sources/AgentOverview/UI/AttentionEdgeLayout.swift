import QuartzCore

/// What an edge cue beside a row says: the row waits for the person (`waiting`, amber in every colour
/// mode, pulsing with the grow of its kind) or its turn ended and it waits for the next instruction
/// (`yourTurn`, in the row's body colour at a lower opacity, breathing with its halo).
enum AttentionEdgeCue: Equatable, Sendable {
    case waiting(WaitingKind)
    /// The row's body colour (`FaceLook.bodyColor`): the your-turn mint, the project or the identity colour.
    case yourTurn(EyeColor)

    /// The cue a status shows, nil for statuses without one. `bodyColor` is the face's body colour
    /// (`FaceLook.bodyColor`); only the your-turn cue takes it.
    init?(status: FaceStatus, bodyColor: EyeColor) {
        switch status {
        case .needsInput(let kind): self = .waiting(kind)
        case .yourTurn: self = .yourTurn(bodyColor)
        case .working, .idle, .justFinished, .ended: return nil
        }
    }

    /// The bar's colour, its opacity at the top of the loop and the rest fraction (`BlobHalo` levels).
    var halo: BlobHalo {
        switch self {
        case .waiting:
            BlobHalo(color: Theme.needsInputColor, opacity: Theme.attentionEdgeOpacity, restFraction: Theme.attentionHaloRestFraction)
        case .yourTurn(let color):
            BlobHalo(color: color, opacity: Theme.yourTurnEdgeOpacity, restFraction: Theme.yourTurnHaloPulse.scale, breath: Theme.yourTurnHaloPulse)
        }
    }

    /// The bar's opacity loop, in step with the face's halo (same timing, same seeded phase).
    func loop(phase: Double) -> CAKeyframeAnimation {
        switch self {
        case .waiting(let kind):
            BlobAnimations.haloGrow(halo, grow: BlobProgramBuilder.attentionGrow(for: kind), phase: phase)
        case .yourTurn:
            BlobAnimations.haloBreath(halo, breath: Theme.yourTurnHaloPulse, phase: phase)
        }
    }
}

/// Where the edge cue of a waiting or your-turn row sits: a `Theme.attentionEdgeWidth` wide line flush
/// with the capsule's inner edge (the left edge on the right side, the right edge on the left side),
/// centred on the row's slot, `Theme.attentionEdgeLengthFraction` of the row pitch long. In the
/// capsule content's coordinates (`Theme.contentWidth` wide, origin top-left).
@MainActor
enum AttentionEdgeLayout {
    /// The cue's rectangle for `slot` in a capsule with `rows` live rows, `actions` action rows and,
    /// with `newSession`, the new session button above them, on the panel's `side`.
    static func rect(slot: Int, rows: Int, actions: Int, newSession: Bool = false, side: PanelSide = .default) -> CGRect {
        let height = Theme.rowPitch * Theme.attentionEdgeLengthFraction
        let centerY = PanelModel.slotCenterY(slot: slot, rows: rows, actions: actions, newSession: newSession)
        let canonical = CGRect(
            x: GooLayout.capsuleLeft + Theme.attentionEdgeInset,
            y: centerY - height / 2,
            width: Theme.attentionEdgeWidth,
            height: height
        )
        return side.mirror(canonical, in: Theme.contentWidth)
    }
}
