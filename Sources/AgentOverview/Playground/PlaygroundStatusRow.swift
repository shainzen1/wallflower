import SwiftUI

/// The six status loops at hero size (needs input, working, your turn, idle, just finished, ended), plus
/// the action face at rest. In `.project` colour mode every status hero gets its own sample project
/// key, so the row shows different hues. The row tracks the pointer (`onPointer`, in the row's own
/// coordinates) and applies the hover effect at hero size: under `.magnify` every hero gets its
/// magnification from the pointer's distance along the row, under `.stretch` the hero under the
/// pointer is hovered. `look.hovered` hovers every hero regardless (the `--hovered` argument).
struct PlaygroundStatusRow: View {
    let seed: String
    let look: PlaygroundLook
    /// The pointer over the row, in the row's coordinates; nil when it is elsewhere.
    var pointer: CGPoint?
    var onPointer: (CGPoint?) -> Void = { _ in }

    /// Horizontal distance between two hero centres (the hero plus the row spacing).
    static let spacing: CGFloat = 20
    static let pitch: CGFloat = PlaygroundView.heroSize + spacing

    /// Fixed so re-renders keep the idle clock running from the same moment.
    private static let idleSince = Date()

    private var statuses: [(label: String, status: FaceStatus)] {
        [
            ("needs input", .needsInput(kind: look.waitingKind)),
            ("working", .working),
            ("your turn", .yourTurn(since: Self.idleSince)),
            ("idle", .idle(since: Self.idleSince)),
            ("just finished", .justFinished),
            ("ended", .ended),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaygroundLabel("Status loops (colour mode: \(look.colorMode.rawValue))")
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { index, entry in
                    VStack(spacing: 6) {
                        look.styled(FaceView(seed: "\(seed)-\(index)", status: entry.status, size: PlaygroundView.heroSize))
                            .project(look.projectKey(column: index))
                            .activity(look.activity)
                            .satellites(look.satellites)
                            .attention(token: entry.status.isNeedsInput ? look.attentionToken : 0)
                            .excited(token: look.excitedToken)
                            .hovered(hovered(column: index))
                            .magnify(magnify(column: index))
                        PlaygroundLabel(entry.status == .working ? "working · \(look.activity.rawValue)" : entry.status.isNeedsInput ? "needs input · \(look.waitingKind.label)" : entry.label)
                    }
                }
                VStack(spacing: 6) {
                    let hovered = hovered(column: statuses.count)
                    look.styled(FaceView(seed: "\(seed)-action", action: ActionFace(phase: hovered ? .hovered : .resting), size: PlaygroundView.heroSize))
                        .hovered(hovered)
                        .magnify(magnify(column: statuses.count))
                    PlaygroundLabel(hovered ? "action · hovered" : "action · resting")
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point): onPointer(point)
                case .ended: onPointer(nil)
                }
            }
        }
    }

    /// Centre of hero `column` in the row's coordinates.
    static func heroCentre(column: Int) -> CGPoint {
        CGPoint(x: PlaygroundView.heroSize / 2 + CGFloat(column) * pitch, y: PlaygroundView.heroSize / 2)
    }

    /// Hovered: every hero with `look.hovered`, else the hero whose square holds the pointer.
    private func hovered(column: Int) -> Bool {
        if look.hovered { return true }
        guard let pointer else { return false }
        let centre = Self.heroCentre(column: column)
        let half = PlaygroundView.heroSize / 2
        return abs(pointer.x - centre.x) <= half && abs(pointer.y - centre.y) <= half
    }

    /// The hero's magnification from the pointer's distance along the row (`.magnify` only).
    private func magnify(column: Int) -> MagnifyState {
        guard look.hoverEffect == .magnify, let pointer else { return .identity }
        let centre = Self.heroCentre(column: column)
        let offset = CGPoint(x: pointer.x - centre.x, y: pointer.y - centre.y)
        return MagnifyState.at(
            offset: offset, distance: abs(offset.x), spread: 1.1 * Self.pitch, faceSize: PlaygroundView.heroSize,
            followReach: CGSize(width: Self.pitch / 2, height: PlaygroundView.heroSize / 2), maxScale: Theme.magnifyMax
        )
    }
}
