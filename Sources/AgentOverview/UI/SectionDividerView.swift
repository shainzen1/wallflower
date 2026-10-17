import SwiftUI

/// The section break between the live rows and the action faces: a 1 pt line in
/// `Theme.dividerColor`, `Theme.dividerWidthFraction` of the capsule's width, centred in the
/// capsule column. A plain SwiftUI view over the goo; the black body stays one shape.
/// Its frame is the divider band, `Theme.dividerHeight` tall.
struct SectionDividerView: View {
    /// Height this view takes in the row stack (the stack has no spacing: rows are a pitch tall each).
    static let stackHeight = Theme.dividerHeight
    /// The screen edge the capsule column sits at.
    var side: PanelSide = .default

    var body: some View {
        EdgeRow(side: side, height: Self.stackHeight) {
            EmptyView()
        } face: {
            Rectangle()
                .fill(Theme.dividerColor)
                .frame(width: Theme.capsuleWidth * Theme.dividerWidthFraction, height: Theme.dividerLineWidth)
                .frame(width: Theme.capsuleWidth, height: Self.stackHeight)
        }
        .allowsHitTesting(false)
    }
}
