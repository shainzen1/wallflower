import AppKit

/// Where the auto-hide edge trigger sits: pure geometry, testable (`PanelPlacement` style).
///
/// A strip `width` wide on the screen edge of `side`, as tall as the panel's window (its band on the
/// edge). The panel is hidden while the trigger exists, so the band is where it would come out.
enum EdgeTriggerPlacement {
    /// The trigger's frame for a panel window at `panelFrame` on a screen at `screenFrame`.
    static func frame(panelFrame: NSRect, screenFrame: NSRect, side: PanelSide, width: CGFloat) -> NSRect {
        NSRect(
            x: side.isMirrored ? screenFrame.minX : screenFrame.maxX - width,
            y: panelFrame.minY,
            width: width,
            height: panelFrame.height
        )
    }

    /// Whether another screen continues past the panel's edge in its band (`band`, the panel frame's
    /// vertical span): the pointer then crosses the edge instead of stopping at it.
    static func sharesEdge(screenFrame: NSRect, side: PanelSide, band: NSRect, otherScreens: [NSRect]) -> Bool {
        let edge = side.isMirrored ? screenFrame.minX : screenFrame.maxX
        return otherScreens.contains { other in
            let touches = side.isMirrored ? abs(other.maxX - edge) < 1 : abs(other.minX - edge) < 1
            return touches && other.maxY > band.minY && other.minY < band.maxY
        }
    }

    /// The trigger's width: `Theme.autoHideTriggerWidth` at an outer edge, wider on a shared one.
    static func width(sharesEdge: Bool) -> CGFloat {
        sharesEdge ? Theme.autoHideSharedEdgeTriggerWidth : Theme.autoHideTriggerWidth
    }
}

/// The auto-hide edge trigger: an invisible strip a few points wide on the panel's screen edge, in
/// the panel's band, ordered in only while the panel is hidden (`PanelWindow.setConcealed`). It
/// carries one `NSTrackingArea` (enter and exit, active always), so it costs nothing at rest and needs
/// no permission. The pointer resting in it for `Theme.autoHideDwell` brings the panel out
/// (`onReveal`); a pointer crossing it on its way to a neighbouring display leaves before that. A
/// click in it brings the panel out at once. Same level, Spaces and full-screen behaviour as the panel.
final class EdgeTriggerWindow: NSPanel {
    /// The pointer rested in the strip, or clicked it.
    var onReveal: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Theme.autoHideTriggerWidth, height: 1), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        // The window server lets clicks and pointer tracking through pixels of alpha 0; the barest tint
        // (a few levels of 255, invisible on a 2 pt strip) keeps the strip under the pointer.
        backgroundColor = NSColor.black.withAlphaComponent(0.01)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = EdgeTriggerView()
        view.onReveal = { [weak self] in self?.onReveal?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The trigger's content: the tracking area and the dwell.
private final class EdgeTriggerView: NSView {
    var onReveal: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var dwell: Task<Void, Never>?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        dwell?.cancel()
        dwell = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Theme.autoHideDwell))
            guard !Task.isCancelled, let self else { return }
            self.dwell = nil
            // Still in the strip (an exit may not have arrived yet when the pointer left fast).
            guard let window = self.window, window.isVisible, window.frame.contains(NSEvent.mouseLocation) else { return }
            self.onReveal?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        dwell?.cancel()
        dwell = nil
    }

    override func mouseDown(with event: NSEvent) {
        dwell?.cancel()
        dwell = nil
        onReveal?()
    }
}
