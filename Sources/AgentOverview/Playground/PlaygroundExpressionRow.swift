import SwiftUI

/// One hero face per column showing the cycled expression, so the transitions are visible large.
struct PlaygroundExpressionRow: View {
    let seed: String
    let expression: Expression
    let look: PlaygroundLook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaygroundLabel("Expression: \(expression.label)")
            HStack(alignment: .top, spacing: 20) {
                ForEach(look.columns) { column in
                    VStack(spacing: 6) {
                        look.styled(FaceView(seed: seed, expression: expression, size: PlaygroundView.heroSize))
                            .identity(column.identity(seed: seed))
                            .blobBody(column.body)
                        PlaygroundLabel(column.label)
                    }
                }
            }
        }
    }
}
