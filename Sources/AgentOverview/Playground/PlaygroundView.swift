import SwiftUI

/// Root of the eye playground. Black background, quiet grey labels, so the faces are judged
/// and not the chrome. Top: the five status loops at hero size. Middle: one hero face per
/// column (preset, status shape or silhouette) showing the cycled expression. Bottom: every
/// expression x every column at panel size.
struct PlaygroundView: View {
    let model = PlaygroundModel()

    static let heroSize: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            // The five heroes fill the window's width; the bulge sample sits right under them.
            PlaygroundStatusRow(seed: model.seed, look: model.look, pointer: model.heroPointer) { model.heroPointerMoved(to: $0) }
            PlaygroundBulgeSample(activity: model.activity)
            PlaygroundExpressionRow(seed: model.seed, expression: model.expression, look: model.look)
            PlaygroundGrid(seed: model.seed, look: model.look)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button("Cycle expression") { model.cycleExpression() }
                Button("Blink now") { model.blinkNow() }
                Button("Replay finished") { model.replayFinished() }
                Button("Style: \(model.style.label)") { model.cycleStyle() }.fixedSize()
                Button("Filter: \(model.filter.label)") { model.cycleFilter() }.fixedSize()
                if model.style == .blob {
                    Button("Shape: \(model.shapeMode == .status ? "status" : "identity")") { model.toggleShapeMode() }.fixedSize()
                }
                Button("Colour: \(model.colorMode.rawValue)") { model.cycleColorMode() }.fixedSize()
                Spacer(minLength: 8)
                TextField("Seed", text: model.seedBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { model.applySeed() }
                Button("Re-roll") { model.applySeed() }
            }
            HStack(spacing: 10) {
                Button("Working: \(model.activity.rawValue)") { model.cycleActivity() }.fixedSize()
                Button("Satellites: \(model.satellites)") { model.cycleSatellites() }.fixedSize()
                Button("Hop") { model.hop() }
                Button("Excite") { model.excite() }
                Button("Kind: \(model.waitingKind.label)") { model.toggleWaitingKind() }.fixedSize()
                Button("Hover effect: \(model.hoverEffect.rawValue)") { model.cycleHoverEffect() }.fixedSize()
                Spacer(minLength: 8)
            }
        }
        .controlSize(.small)
        .font(.system(size: 11))
    }
}
