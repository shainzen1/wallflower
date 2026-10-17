import SwiftUI

/// The thin line beside a waiting (amber) or your-turn (the row's body colour) row on the capsule's
/// inner edge (left on the right side, right on the left side).
/// SwiftUI places it (the row spring moves it on reorders); its pulse is a Core Animation opacity
/// loop in step with the row's halo (same timing, same seeded phase), so nothing ticks in the app.
/// While the row's bulge is open the line hides (the bulge covers the edge).
struct AttentionEdgeCueView: NSViewRepresentable {
    let cue: AttentionEdgeCue
    /// The face's pulse phase, so the line and the halo rise together.
    let phase: Double
    /// False while the row's own bulge is open.
    let visible: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> AttentionEdgeHostView {
        let view = AttentionEdgeHostView(frame: CGRect(x: 0, y: 0, width: Theme.attentionEdgeWidth, height: Theme.rowPitch))
        view.apply(cue: cue, phase: phase, visible: visible, reduceMotion: reduceMotion, animated: false)
        return view
    }

    func updateNSView(_ view: AttentionEdgeHostView, context: Context) {
        view.apply(cue: cue, phase: phase, visible: visible, reduceMotion: reduceMotion, animated: true)
    }
}
