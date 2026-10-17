import SwiftUI

/// Four real faces, one per status a person cares about (needs you, working, idle, done), each with
/// a small label under it. Used by the Appearance preview and the welcome window. No session behind
/// them: each `FaceView` is driven by a fixed status, with the look passed in explicitly so a change
/// in Settings shows here at once.
struct StatusFaceSamples: View {
    /// What the faces are drawn with.
    var look: PanelLook
    /// When the idle face fell idle: fixed per window, so a re-render never restarts its loops, and
    /// recent, so it is awake (sleepy comes after `Theme.sleepyAfter`).
    var idleSince: Date
    var faceSize: CGFloat
    var spacing: CGFloat
    var labelFont: Font = .caption
    var labelColor: Color = .white.opacity(0.62)
    var labelGap: CGFloat = 8

    /// Seeds and sample project keys stay fixed, so the faces keep their identity across changes.
    private var samples: [(label: String, status: FaceStatus)] {
        [
            ("Needs you", .needsInput(kind: .question)),
            ("Working", .working),
            ("Idle", .idle(since: idleSince)),
            ("Done", .justFinished),
        ]
    }

    private static let projectKeys = ProjectColor.sampleKeys(count: 4)

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                VStack(spacing: labelGap) {
                    StatusFace(look: look, status: sample.status, seed: "sample-\(index)", size: faceSize, projectKey: projectKey(index))
                    Text(sample.label)
                        .font(labelFont)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minWidth: faceSize)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// In `.project` colour mode every sample belongs to one project, so the preview shows what that
    /// mode means: the project's hue working, dimmed at rest, with the mint flash when done, and the
    /// amber of needs input whatever the project.
    private func projectKey(_ index: Int) -> String? {
        guard look.colorMode == .project else { return nil }
        return Self.projectKeys.first
    }
}

/// One face for a fixed status in an explicit look.
struct StatusFace: View {
    var look: PanelLook
    var status: FaceStatus
    var seed: String
    var size: CGFloat
    var projectKey: String?

    var body: some View {
        FaceView(seed: seed, status: status, size: size)
            .faceStyle(look.faceStyle)
            .faceFilter(look.faceFilter)
            .blobShapeMode(look.blobShapeMode)
            .colorMode(look.colorMode)
            .hoverEffect(.none)
            .project(projectKey)
            .accessibilityHidden(true)
    }
}
