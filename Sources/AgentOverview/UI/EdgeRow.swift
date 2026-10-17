import SwiftUI

/// The horizontal order of one capsule row, the one place it is decided for every row type: the
/// face column sits at the screen edge and the bulge content beside it, away from the edge, with
/// the slack beyond. On the right edge that is slack, bulge, face; on the left edge face, bulge, slack.
/// The row is `Theme.contentWidth` wide and `height` tall.
struct EdgeRow<Bulge: View, Face: View>: View {
    let side: PanelSide
    var height: CGFloat = Theme.faceSize
    @ViewBuilder let bulge: Bulge
    @ViewBuilder let face: Face

    var body: some View {
        HStack(spacing: 0) {
            if side.isMirrored {
                face
                bulge
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                bulge
                face
            }
        }
        .frame(width: Theme.contentWidth, height: height)
    }
}

/// The text block of a bulge, aligned for the panel's side: on the right edge left-aligned at the
/// bulge's outer padding with the face gap toward the face; on the left edge mirrored, right-aligned
/// at the outer padding with the face gap on its left. Width `reach`, height `height`.
struct BulgeTextFrame: ViewModifier {
    let side: PanelSide
    let reach: CGFloat
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: side.isMirrored ? .trailing : .leading)
            .padding(side.isMirrored ? .trailing : .leading, Theme.bulgeInnerPadding)
            .padding(side.isMirrored ? .leading : .trailing, Theme.bulgeTextFaceGap)
            .frame(width: reach, height: height)
    }
}

extension PanelSide {
    /// The alignment of the bulge's text lines: leading on the right edge, trailing (mirrored) on the left.
    var bulgeTextAlignment: HorizontalAlignment { isMirrored ? .trailing : .leading }
}
