import AppKit

/// Moves the panel up and down the screen edge when a press on it turns into a vertical drag.
///
/// A local event monitor sees the left-button events of the panel before the window dispatches them,
/// so SwiftUI keeps getting every event of a plain click (press feedback through `RowPressStyle`,
/// first click on the never-key panel, the button action on release). A press stays a click until the
/// pointer moved more than `Theme.dragThreshold` vertically (`PanelDragTracker`); from then on the
/// window follows the pointer 1:1, the dragged events are kept from SwiftUI, pointer reports to the
/// model are frozen and the model swallows the tap the release may still produce. The release itself
/// is passed on, so the button's pressed look ends normally.
///
/// Throw: a press on a session face that first travels more than `Theme.throwThreshold` away from the
/// screen edge (to the left on the right edge, to the right on the left edge; before
/// `Theme.dragThreshold` vertically, `PressAxis`) holds the face instead (`FaceThrow`): the
/// model moves that face with the pointer, the dragged events are kept from SwiftUI, and the release
/// either throws it out (the session is hidden) or springs it back. A vertical first movement is the
/// panel drag exactly as before; the axis is decided once per press.
///
/// The monitor only runs while events arrive; at rest it costs nothing.
@MainActor
final class PanelDragController {
    /// Receives the offset a drag ended at (the clamped anchor), for persisting.
    var onDragEnded: ((CGFloat) -> Void)?

    private weak var panel: PanelWindow?
    private weak var hostingView: PanelHostingView?
    private weak var model: PanelModel?
    private var tracker: PanelDragTracker?
    /// The current press: where it went down (screen points), what it became, the held face.
    private var press: Press?
    private var monitor: Any?

    private struct Press {
        let start: CGPoint
        /// Event time of the press.
        let startTime: TimeInterval
        /// The session face under the press, nil when the press cannot throw.
        let throwKey: SessionKey?
        var axis = PressAxis.click
        var faceThrow: FaceThrow?
    }

    init(panel: PanelWindow, hostingView: PanelHostingView, model: PanelModel) {
        self.panel = panel
        self.hostingView = hostingView
        self.model = model
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let window = event.window
            let location = event.locationInWindow
            let time = event.timestamp
            // Screen position of the pointer at this event. The window moves with the drag, so the
            // window-relative location alone would feed back into itself.
            let pointer = window?.convertPoint(toScreen: location) ?? NSEvent.mouseLocation
            let passesOn = MainActor.assumeIsolated {
                self?.handle(type: type, window: window, location: location, pointer: pointer, time: time) ?? true
            }
            return passesOn ? event : nil
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Returns whether the event goes on to the window (false swallows it).
    private func handle(type: NSEvent.EventType, window: NSWindow?, location: CGPoint, pointer: CGPoint, time: TimeInterval) -> Bool {
        guard let panel, window === panel else { return true }
        let pointerY = pointer.y
        switch type {
        case .leftMouseDown:
            tracker = PanelDragTracker(startPointerY: pointerY, startOffset: panel.appliedOffset)
            press = Press(start: pointer, startTime: time, throwKey: throwTarget(atWindowLocation: location))
            model?.pressBegan()
            return true
        case .leftMouseDragged:
            if var press {
                if press.axis == .click {
                    let side = model?.side ?? .default
                    press.axis = PressAxis.decide(
                        dx: pointer.x - press.start.x, dy: pointer.y - press.start.y, canThrow: press.throwKey != nil, side: side
                    )
                    if press.axis == .throwFace, let key = press.throwKey {
                        press.faceThrow = FaceThrow(key: key, start: press.start, at: press.startTime, side: side)
                        model?.throwBegan(key: key)
                    }
                }
                if var faceThrow = press.faceThrow {
                    faceThrow.moved(to: pointer, at: time)
                    press.faceThrow = faceThrow
                    self.press = press
                    model?.throwMoved(faceThrow)
                    return false
                }
                self.press = press
            }
            guard var tracker else { return true }
            let wasDragging = tracker.isDragging
            if let offset = tracker.pointerMoved(toY: pointerY) {
                if !wasDragging { model?.dragBegan() }
                panel.drag(to: offset)
            }
            self.tracker = tracker
            return !tracker.isDragging
        case .leftMouseUp:
            if var faceThrow = press?.faceThrow {
                faceThrow.moved(to: pointer, at: time)
                press = nil
                tracker = nil
                model?.throwEnded(faceThrow)
                hostingView?.reportCurrentPointer()
                return true
            }
            press = nil
            guard let tracker else { return true }
            self.tracker = nil
            if tracker.isDragging {
                let offset = panel.endDrag()
                model?.dragEnded()
                hostingView?.reportCurrentPointer()
                onDragEnded?(offset)
            }
            return true
        default:
            return true
        }
    }

    /// The session face a press at a window location could throw (the model decides, in the hosting
    /// view's top-left coordinates).
    private func throwTarget(atWindowLocation location: CGPoint) -> SessionKey? {
        guard let hostingView, let model else { return nil }
        var point = hostingView.convert(location, from: nil)
        if !hostingView.isFlipped { point.y = hostingView.bounds.height - point.y }
        return model.throwTarget(atViewPoint: point, in: hostingView.bounds.size)
    }
}
