import SwiftUI

/// Every expression (rows) for every column (presets, status shapes or silhouettes) at panel
/// size, for judging the shapes. Columns cycle through the palette so the colours are visible too.
struct PlaygroundGrid: View {
    let seed: String
    let look: PlaygroundLook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaygroundLabel("All expressions at \(Int(Theme.faceSize)) pt")
            ScrollView(.vertical) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Color.clear.frame(width: 90, height: 1)
                        ForEach(look.columns) { column in
                            PlaygroundLabel(column.label).frame(width: Theme.faceSize + 8)
                        }
                    }
                    ForEach(Expression.allCases, id: \.self) { expression in
                        GridRow {
                            PlaygroundLabel(expression.label)
                                .frame(width: 90, alignment: .leading)
                            ForEach(Array(look.columns.enumerated()), id: \.element.id) { index, column in
                                look.styled(FaceView(seed: seed, expression: expression))
                                    .identity(identity(column: index, preset: column.preset))
                                    .project(look.projectKey(column: index))
                                    .blobBody(column.body)
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    /// Identity per column: the preset forced (dot matrix), the palette cycled so `.identity`
    /// colour mode shows every colour; in `.status` colour mode the builders show the idle grey, in
    /// `.project` mode the column's sample project colour.
    private func identity(column: Int, preset: EyePreset?) -> FaceIdentity {
        let palette = Theme.eyePalette
        let hash = SeedHash("\(seed)-\(column)")
        return FaceIdentity(color: palette[column % palette.count], preset: preset ?? EyePreset.allCases[column % EyePreset.allCases.count], hash: hash)
    }
}
