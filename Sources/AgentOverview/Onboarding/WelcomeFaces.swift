import SwiftUI

/// "Shape is status": the four states a person acts on, loudest first, each a real face with its
/// name and what it asks of you. Your turn is in it (it is what most faces show between prompts);
/// the mint burst of a finished turn only lasts a moment, so it is left out.
struct WelcomeStatusLegend: View {
    /// Drawn coloured by status, whatever the Colour setting.
    var look: PanelLook
    var idleSince: Date

    private var entries: [(label: String, detail: String, status: FaceStatus)] {
        [
            ("Needs you", "Asked you something", .needsInput(kind: .question)),
            ("Your turn", "Done, over to you", .yourTurn(since: idleSince)),
            ("Working", "Busy, let it run", .working),
            ("Idle", "Resting", .idle(since: idleSince)),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                VStack(spacing: 0) {
                    StatusFace(look: look, status: entry.status, seed: "welcome-status-\(index)", size: 56)
                    Text(entry.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.top, 12)
                    Text(entry.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(WelcomeStyle.tertiary)
                        .padding(.top, 3)
                }
                .lineLimit(1)
                .frame(width: 120)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "Action faces": a session face and an action face as the capsule stacks them (sessions, a thin
/// line, actions), each named, then what a click does and where to add one. One left edge runs
/// through it all: the gesture tiles sit centred under the capsule, their sentences start where the
/// names do.
struct WelcomeActionsPage: View {
    /// The look picked on "Pick a look"; the action face is lavender in every look.
    var look: PanelLook

    private static let faceSize: CGFloat = 34
    /// The piece of capsule around the faces: its width, and the room above and below them.
    private static let capsuleWidth: CGFloat = 46
    private static let capsulePadding: CGFloat = 6
    /// The capsule's line between sessions and actions: the room it takes.
    private static let dividerHeight: CGFloat = 14
    /// From the capsule to the names: they start where the sentences of the rows below do.
    private static let nameGap = (capsuleWidth - gestureTile) / 2 + gestureTile + 16 - capsuleWidth
    /// `WelcomeGestureRow`'s tile.
    private static let gestureTile: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Action faces")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Self.nameGap) {
                    capsule
                    VStack(alignment: .leading, spacing: 0) {
                        kind("Session", "An agent at work")
                        Color.clear.frame(width: 1, height: Self.dividerHeight)
                        kind("Action", "A prompt you saved")
                    }
                    // Level with the faces inside the capsule.
                    .padding(.vertical, Self.capsulePadding)
                }
                VStack(alignment: .leading, spacing: 12) {
                    WelcomeGestureRow(symbol: "cursorarrow.click.2", text: "Click it to start a new session with that prompt.")
                    WelcomeGestureRow(symbol: "plus", text: "Add yours in Settings > General > Actions.")
                }
                .padding(.leading, (Self.capsuleWidth - Self.gestureTile) / 2)
                .padding(.top, 26)
            }
            .padding(.top, 26)
        }
    }

    /// A short piece of the capsule: a working session face above the line, an action face below it.
    private var capsule: some View {
        VStack(spacing: 0) {
            StatusFace(look: look, status: .working, seed: "welcome-actions-session", size: Self.faceSize)
            Rectangle()
                .fill(Theme.dividerColor)
                .frame(width: Self.capsuleWidth * Theme.dividerWidthFraction, height: Theme.dividerLineWidth)
                .frame(height: Self.dividerHeight)
            FaceView(seed: "welcome-actions-action", action: ActionFace(phase: .hovered), size: Self.faceSize)
                .faceStyle(look.faceStyle)
                .faceFilter(look.faceFilter)
                .blobShapeMode(look.blobShapeMode)
                .hoverEffect(.none)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Self.capsulePadding)
        .frame(width: Self.capsuleWidth)
        // Filled only: a hairline around a shape this narrow left two stray lines at its ends.
        .background(WelcomeStyle.panelFill, in: Capsule())
    }

    /// A name and one line beside a face, centred on it.
    private func kind(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WelcomeStyle.secondary)
        }
        .frame(height: Self.faceSize)
        .accessibilityElement(children: .combine)
    }
}
