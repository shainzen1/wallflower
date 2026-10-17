import AppKit
import SwiftUI

/// Hosting view of the panel. The panel never becomes key, so the first click must count:
/// `acceptsFirstMouse` says so for the SwiftUI content.
///
/// It also owns the one `NSTrackingArea` of the app, over its whole visible rect (the view is
/// wider than the collapsed window; the part beyond the window's inner edge is neither visible nor tracked),
/// with `.activeAlways` so hover works although the panel is never key. Every pointer position is
/// handed to `pointerHandler` in top-left coordinates of this view (nil when the pointer left
/// the window); `PanelModel` decides which row that is and whether the bulge opens or melts.
/// Mouse-moved events only arrive while the pointer moves, so a resting pointer costs nothing.
final class PanelHostingView: NSHostingView<PanelRootView> {
    /// Receives the pointer position in this view's top-left coordinates, nil on exit.
    var pointerHandler: ((CGPoint?, CGSize) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        report(event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        report(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointerHandler?(nil, bounds.size)
    }

    /// Reports where the pointer is now, without an event (after a drag, when pointer reports were
    /// frozen while the window moved under it): nil when it is not over the window.
    func reportCurrentPointer() {
        guard let window else { return }
        guard window.frame.contains(NSEvent.mouseLocation) else {
            pointerHandler?(nil, bounds.size)
            return
        }
        var point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if !isFlipped { point.y = bounds.height - point.y }
        pointerHandler?(point, bounds.size)
    }

    /// Converts the event location to this view's top-left coordinate space.
    private func report(_ event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        if !isFlipped { point.y = bounds.height - point.y }
        pointerHandler?(point, bounds.size)
    }
}
