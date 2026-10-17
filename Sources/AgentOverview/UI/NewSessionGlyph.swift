import AppKit
import SwiftUI

/// The new session button's glyph: a ring with a plus inside, both `CAShapeLayer`s filled with their
/// stroke outlines (so the snapshot walk, which fills shape layers, draws them too). No eyes, no glow.
/// At rest both are `Theme.newSessionRestColor`; hovered they turn `Theme.newSessionHoverColor` and
/// the plus turns `Theme.newSessionPlusTurn` (ease-out, `Theme.newSessionHoverDuration`), and back.
/// A click dips the ring once. It is never magnified: the hover magnification leaves the button out
/// (`PanelModel.magnify(slot:)`), so the ring keeps its size while the faces below it grow.
/// Everything runs in Core Animation; nothing loops, so the button costs nothing at rest.
struct NewSessionGlyphState: Equatable, Sendable {
    var hovered = false
    /// Bumped per click: the ring dips once.
    var clickToken = 0
    /// Reduce Motion: no turn, no scale dip (a short fade dip instead).
    var reduceMotion = false
}

enum NewSessionGlyph {
    /// The ring's fill path: the outline of a `stroke` wide circle of `diameter`, inside `box`'s centre square.
    static func ringPath(in box: CGRect, diameter: CGFloat = Theme.newSessionSize, stroke: CGFloat = Theme.newSessionStrokeWidth) -> CGPath {
        let circle = CGRect(x: box.midX - diameter / 2, y: box.midY - diameter / 2, width: diameter, height: diameter)
            .insetBy(dx: stroke / 2, dy: stroke / 2)
        return CGPath(ellipseIn: circle, transform: nil)
            .copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    /// The plus's fill path: two `stroke` wide arms with round caps, each `Theme.newSessionPlusFraction`
    /// of `diameter` long, crossing at `box`'s centre.
    static func plusPath(in box: CGRect, diameter: CGFloat = Theme.newSessionSize, stroke: CGFloat = Theme.newSessionStrokeWidth) -> CGPath {
        let arm = diameter * Theme.newSessionPlusFraction / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: box.midX - arm, y: box.midY))
        path.addLine(to: CGPoint(x: box.midX + arm, y: box.midY))
        path.move(to: CGPoint(x: box.midX, y: box.midY - arm))
        path.addLine(to: CGPoint(x: box.midX, y: box.midY + arm))
        return path.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// The plus's turn for a state (clockwise on screen; none under Reduce Motion).
    static func plusAngle(_ state: NewSessionGlyphState) -> CGFloat {
        state.hovered && !state.reduceMotion ? -Theme.newSessionPlusTurn : 0
    }

    /// Ring and plus colour for a state.
    static func color(_ state: NewSessionGlyphState) -> CGColor {
        state.hovered ? Theme.newSessionHoverColor : Theme.newSessionRestColor
    }
}

/// Layer-hosting view of the glyph: `press` (the click dip) > ring and plus (the plus turns about the centre).
@MainActor
final class NewSessionHostView: NSView {
    private let pressLayer = CALayer()
    private let ring = CAShapeLayer()
    private let plus = CAShapeLayer()
    private var applied: NewSessionGlyphState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        root.addSublayer(pressLayer)
        pressLayer.addSublayer(ring)
        pressLayer.addSublayer(plus)
        layoutLayers(size: frameRect.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The panel never becomes key; a click on the button must count the first time.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for layer in [pressLayer, ring, plus] { layer.contentsScale = scale }
    }

    private func layoutLayers(size: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let box = CGRect(origin: .zero, size: size)
        for layer in [pressLayer, ring, plus] {
            layer.bounds = box
            layer.position = CGPoint(x: box.midX, y: box.midY)
        }
        ring.path = NewSessionGlyph.ringPath(in: box)
        plus.path = NewSessionGlyph.plusPath(in: box)
        let color = NewSessionGlyph.color(applied ?? NewSessionGlyphState())
        ring.fillColor = color
        plus.fillColor = color
        CATransaction.commit()
    }

    func apply(_ state: NewSessionGlyphState) {
        let previous = applied
        applied = state
        guard previous != state else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let color = NewSessionGlyph.color(state)
        let angle = NewSessionGlyph.plusAngle(state)
        let turn = CATransform3DMakeRotation(angle, 0, 0, 1)
        if let previous, previous.hovered != state.hovered || previous.reduceMotion != state.reduceMotion {
            for layer in [ring, plus] {
                let fade = CABasicAnimation(keyPath: "fillColor")
                fade.fromValue = (layer.presentation() ?? layer).fillColor
                fade.toValue = color
                fade.duration = Theme.newSessionHoverDuration
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(fade, forKey: "hover.color")
            }
            if !state.reduceMotion {
                let spin = CABasicAnimation(keyPath: "transform")
                spin.fromValue = (plus.presentation() ?? plus).transform
                spin.toValue = turn
                spin.duration = Theme.newSessionHoverDuration
                spin.timingFunction = CAMediaTimingFunction(name: .easeOut)
                plus.add(spin, forKey: "hover.turn")
            }
        }
        ring.fillColor = color
        plus.fillColor = color
        plus.transform = turn

        if let previous, state.clickToken > previous.clickToken {
            let dip: CAKeyframeAnimation
            if state.reduceMotion {
                dip = CAKeyframeAnimation(keyPath: "opacity")
                dip.values = [1, Theme.newSessionClickReduceMotionOpacity, 1]
            } else {
                dip = CAKeyframeAnimation(keyPath: "transform.scale")
                dip.values = [1, Theme.newSessionClickScale, 1]
            }
            dip.keyTimes = [0, 0.35, 1]
            dip.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            dip.duration = Theme.newSessionClickDuration
            pressLayer.add(dip, forKey: "click")
        }
    }
}

/// SwiftUI host of `NewSessionHostView`, a face-sized square.
struct NewSessionGlyphView: NSViewRepresentable {
    let state: NewSessionGlyphState

    func makeNSView(context: Context) -> NewSessionHostView {
        let view = NewSessionHostView(frame: CGRect(x: 0, y: 0, width: Theme.faceSize, height: Theme.faceSize))
        view.apply(state)
        return view
    }

    func updateNSView(_ view: NewSessionHostView, context: Context) {
        view.apply(state)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NewSessionHostView, context: Context) -> CGSize? {
        CGSize(width: Theme.faceSize, height: Theme.faceSize)
    }
}
