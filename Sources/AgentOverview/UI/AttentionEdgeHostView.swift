import AppKit

/// Layer-hosting view of one edge cue: a rounded bar whose opacity loops with the row's halo
/// (`AttentionEdgeCue.loop`: the grow of a waiting row, the breath of a your-turn one, at the cue's
/// own opacity levels). Visibility fades on a `host` layer above it, so hiding never restarts the
/// loop; a change of cue (your turn to waiting) eases the colour.
@MainActor
final class AttentionEdgeHostView: NSView {
    private let host = CALayer()
    private let bar = CALayer()
    private var installed: (cue: AttentionEdgeCue, phase: Double, reduceMotion: Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        root.addSublayer(host)
        host.addSublayer(bar)
        bar.backgroundColor = Theme.needsInputColor.cgColor
        bar.cornerRadius = Theme.attentionEdgeWidth / 2
        host.opacity = 0
        for layer in [root, host, bar] {
            layer.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), "sublayers": NSNull(), "bounds": NSNull(), "position": NSNull()]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [host, bar] {
            layer.frame = bounds
        }
        CATransaction.commit()
    }

    /// The panel never becomes key; the cue must not swallow the click meant for the row below it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(cue: AttentionEdgeCue, phase: Double, visible: Bool, reduceMotion: Bool, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if installed?.cue != cue || installed?.phase != phase || installed?.reduceMotion != reduceMotion {
            let colorChanged = installed.map { $0.cue.halo.color != cue.halo.color } ?? false
            installed = (cue, phase, reduceMotion)
            let halo = cue.halo
            if colorChanged, animated {
                bar.add(EyeAnimations.color(keyPath: "backgroundColor", from: (bar.presentation() ?? bar).backgroundColor, to: halo.color.cgColor), forKey: "color")
            }
            bar.backgroundColor = halo.color.cgColor
            bar.removeAnimation(forKey: "loop.pulse")
            bar.opacity = Float(halo.opacity * halo.restFraction)
            if !reduceMotion {
                bar.add(cue.loop(phase: phase), forKey: "loop.pulse")
            }
        }
        let to: Float = visible ? 1 : 0
        if host.opacity != to || !animated {
            let from = animated ? (host.presentation() ?? host).opacity : 0
            host.add(BlobAnimations.haloFade(from: from, to: Double(to)), forKey: "fade")
            host.opacity = to
        }
        CATransaction.commit()
    }
}
