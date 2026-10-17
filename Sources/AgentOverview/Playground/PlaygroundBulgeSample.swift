import SwiftUI

/// A static mock of the open bulge next to the status row: project dot, name, the working
/// status with its activity, and the branch line, on the capsule's black, to judge the look.
struct PlaygroundBulgeSample: View {
    let activity: SessionActivity

    /// Fixed so the duration reads `2m` on every render.
    private static let since = Date().addingTimeInterval(-2 * 60)

    private var row: SessionRow {
        SessionRow(
            pid: 1, name: "wallflower", status: .working, stateSince: Self.since, hostSessionId: nil, ended: false,
            activity: activity, subagentCount: 2, gitBranch: "feature/visual-states", projectKey: "wallflower"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaygroundLabel("Bulge sample")
            BulgeContentView(row: row, visible: true, ticking: false, revealDelay: 0, reach: Theme.bulgeWidth - Theme.bulgeOverlap, reduceMotion: true, action: {})
                .background(
                    RoundedRectangle(cornerRadius: Theme.bulgeCornerRadius, style: .continuous)
                        .fill(Theme.capsuleColor)
                )
                .overlay(
                    // The playground is black too: a hairline shows where the bulge ends.
                    RoundedRectangle(cornerRadius: Theme.bulgeCornerRadius, style: .continuous)
                        .strokeBorder(Color(white: 0.22), lineWidth: 1)
                )
                .allowsHitTesting(false)
        }
    }
}
