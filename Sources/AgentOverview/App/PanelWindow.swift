import AppKit
import os

/// Borderless, non-activating HUD panel docked flush to the right (or, with `side`, the left) edge
/// of the primary screen. It never becomes key or main, lives on every Space and above full-screen apps.
///
/// Space switches: the panel joins a window-server Space of its own (`StationarySpace`, see there for
/// the measurements), so it stays glued to the edge while a full-screen Space slides in or out. The
/// collection behaviour below is what keeps it on every Space when that Space is unavailable.
///
/// Vertical position: `verticalOffset` is the anchor (the window centre's distance from the screen's
/// vertical centre, persisted by `AppDelegate`); `PanelPlacement` clamps it into the visible frame.
final class PanelWindow: NSPanel {
    /// Height of the capsule and therefore of the window. Changing it re-docks the window around
    /// the same vertical anchor (the capsule grows up and down from it, re-clamped to the screen).
    var capsuleHeight: CGFloat {
        didSet { applyFrame(reason: "capsuleHeight") }
    }

    /// The anchor: the window centre's offset from the screen's vertical centre (positive is up).
    /// The window shows it clamped to the visible frame; the anchor itself stays as set, so a capsule
    /// that had to be pushed away from it returns once it fits again.
    var verticalOffset: CGFloat {
        didSet { applyFrame(reason: "offset") }
    }

    /// The screen edge the panel docks to. Changing it moves the window to the other edge and
    /// re-anchors the hosting view on that side, in one step (no relaunch, no animation).
    var side: PanelSide {
        didSet {
            guard side != oldValue else { return }
            placement.side = side
            anchorHostingView()
            applyFrame(reason: "side")
        }
    }

    private(set) var state: PanelWindowState = .collapsed
    /// "Hide panel" in the menu: ordered out until shown again; the screen saver and lock screen
    /// handling does not bring it back meanwhile.
    var isHiddenByUser = false {
        didSet {
            guard isHiddenByUser != oldValue else { return }
            if isHiddenByUser { orderOut(nil) } else if covers.isEmpty { show() }
            updateEdgeTrigger()
        }
    }
    /// Auto-hide: the content slid off the screen edge (`setConcealed`). The window stays where it is,
    /// ignores the pointer, and the edge trigger stands in for it.
    private(set) var isConcealed = false
    /// The pointer rested at the edge in the panel's band (or clicked there) while it is concealed.
    var onEdgeReveal: (() -> Void)?
    /// The edge trigger, created on the first conceal; ordered in only while concealed and shown.
    private var edgeTrigger: EdgeTriggerWindow?
    private var placement: PanelPlacement
    /// The SwiftUI hosting view, anchored to the window's screen-edge side (`install`).
    private weak var hosting: NSView?
    /// The live offset while the person drags the panel, nil otherwise.
    private var dragOffset: CGFloat?
    /// True inside `resetPosition`'s animation group: the frame change goes through the animator.
    private var animatesFrame = false
    /// The panel's own Space, nil when disabled or unavailable.
    private var ownSpace: StationarySpace?
    /// `--log-frame`: log every frame set and every screen, Space or occlusion change.
    private let logsFrame: Bool

    init(capsuleHeight: CGFloat, verticalOffset: CGFloat = 0, side: PanelSide = .default, logsFrame: Bool = false) {
        self.capsuleHeight = capsuleHeight
        self.verticalOffset = verticalOffset
        self.side = side
        placement = PanelPlacement(side: side)
        self.logsFrame = logsFrame
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.capsuleWidth + Theme.windowPadding, height: capsuleHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // The own Space sits above the user Spaces, so it would also sit above the screen saver and
        // the lock screen: step aside while either is up.
        let distributed = DistributedNotificationCenter.default()
        for name in Self.coverNotifications.keys {
            distributed.addObserver(self, selector: #selector(screenCoverDidChange), name: Notification.Name(name), object: nil)
        }
        if logsFrame {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDidChange), name: name, object: self)
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Mounts the SwiftUI hosting view at the full content width (`Theme.contentWidth` plus the
    /// window padding), glued to the screen-edge side of a plain container content view (the right
    /// edge, or the left one on the left side). The window only
    /// ever reveals more or less of it (animation rule 4): a resize never changes the hosting view's
    /// size or where its content sits on the screen, so SwiftUI has no geometry change to animate.
    /// Sized with the window, the capsule's position inside the hosting view would change in the same
    /// update as the hover state, and the goo's `.animation(value:)` would spring it in from the left.
    /// The part beyond the window's inner edge is clipped by the window and never drawn.
    func install(_ hosting: NSView) {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        // Layer-backed explicitly: auto-hide slides the content with this layer's sublayer transform.
        container.wantsLayer = true
        contentView = container
        container.addSubview(hosting)
        self.hosting = hosting
        anchorHostingView()
    }

    /// Glues the hosting view to the container's screen-edge side: its right edge to the container's
    /// right edge (the flexible margin on the left), or on the left side its left edge to the left.
    private func anchorHostingView() {
        guard let hosting, let container = hosting.superview else { return }
        let width = Theme.contentWidth + Theme.windowPadding
        let x = side.isMirrored ? 0 : container.bounds.width - width
        hosting.frame = NSRect(x: x, y: 0, width: width, height: container.bounds.height)
        hosting.autoresizingMask = [side.isMirrored ? .maxXMargin : .minXMargin, .height]
    }

    /// Orders the panel in without activating the app and moves it into its own Space
    /// (created on first use when `Theme.panelOwnSpace` is on).
    func show() {
        orderFrontRegardless()
        if Theme.panelOwnSpace, ownSpace == nil {
            ownSpace = StationarySpace(level: Theme.panelSpaceLevel)
            if ownSpace == nil { DataLog.panel.error("own Space unavailable, the panel will slide with Space switches") }
        }
        ownSpace?.add(self)
        if logsFrame { DataLog.panel.notice("shown, own Space \(self.ownSpace == nil ? 0 : 1)") }
        updateEdgeTrigger()
    }

    // MARK: Auto-hide

    /// Slides the content off the screen edge (`concealed`) or back, along the edge normal: a Core
    /// Animation move of the content view's sublayer transform by the window's width, the Dock's
    /// ease-in away into the edge and ease-out back (`AutoHideSlide`), so the capsule disappears into
    /// the edge and the window clips it; nothing runs once it landed. A slide that turns another
    /// around starts where that one is on screen and takes the share of the time its distance needs.
    /// The window frame never moves, so nothing shows on a display beyond a shared edge. Reduce
    /// Motion: a fade instead. Concealed, the window ignores the pointer and the edge trigger takes
    /// over (`EdgeTriggerWindow`).
    func setConcealed(_ concealed: Bool, animated: Bool) {
        guard concealed != isConcealed else { return }
        isConcealed = concealed
        ignoresMouseEvents = concealed
        if let layer = contentView?.layer {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let slide = concealed && !reduceMotion
                ? CATransform3DMakeTranslation(side.mirror(dx: frame.width), 0, 0)
                : CATransform3DIdentity
            let opacity: Float = concealed && reduceMotion ? 0 : 1
            let fromSlide = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
            let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayerTransform = slide
            // Through AppKit's own property, which owns the layer's opacity.
            contentView?.alphaValue = CGFloat(opacity)
            CATransaction.commit()
            if animated {
                if !CATransform3DEqualToTransform(fromSlide, slide) {
                    let motion = AutoHideSlide.toward(concealed: concealed)
                    let curve = motion.curve
                    // The slide only translates along x: the share of the full travel still ahead.
                    let remaining = frame.width > 0 ? abs(Double(slide.m41 - fromSlide.m41) / Double(frame.width)) : 1
                    let animation = CABasicAnimation(keyPath: "sublayerTransform")
                    animation.fromValue = NSValue(caTransform3D: fromSlide)
                    animation.toValue = NSValue(caTransform3D: slide)
                    animation.duration = motion.duration(remaining: remaining)
                    animation.timingFunction = CAMediaTimingFunction(controlPoints: curve.0, curve.1, curve.2, curve.3)
                    layer.add(animation, forKey: "autoHideSlide")
                }
                if fromOpacity != opacity {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.fromValue = fromOpacity
                    animation.toValue = opacity
                    animation.duration = Theme.autoHideFadeDuration
                    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    layer.add(animation, forKey: "autoHideFade")
                }
            }
        }
        if logsFrame { DataLog.panel.notice("auto-hide: \(concealed ? "concealed" : "revealed", privacy: .public), animated \(animated ? 1 : 0), frame \(Self.describe(self.frame), privacy: .public)") }
        updateEdgeTrigger()
    }

    /// Whether the pointer is on the window (a point of slack around it).
    var isPointerOnPanel: Bool {
        frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    /// The edge trigger while it is ordered in (scripted checks click it, `--gesture-script edge`).
    var visibleEdgeTrigger: NSWindow? {
        edgeTrigger?.isVisible == true ? edgeTrigger : nil
    }

    /// Orders the edge trigger in (at the panel's band on its edge, wider on an edge shared with
    /// another display) while the panel is concealed and would otherwise show, and out otherwise.
    private func updateEdgeTrigger() {
        let wanted = isConcealed && isVisible && !isHiddenByUser && covers.isEmpty
        guard wanted, let screen = Self.dockScreen else {
            if edgeTrigger?.isVisible == true {
                edgeTrigger?.orderOut(nil)
                if logsFrame { DataLog.panel.notice("edge trigger out") }
            }
            return
        }
        let trigger = edgeTrigger ?? EdgeTriggerWindow()
        if edgeTrigger == nil {
            trigger.onReveal = { [weak self] in self?.onEdgeReveal?() }
            edgeTrigger = trigger
        }
        let others = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        let shared = EdgeTriggerPlacement.sharesEdge(screenFrame: screen.frame, side: side, band: frame, otherScreens: others)
        let triggerFrame = EdgeTriggerPlacement.frame(
            panelFrame: frame, screenFrame: screen.frame, side: side, width: EdgeTriggerPlacement.width(sharesEdge: shared)
        )
        let wasVisible = trigger.isVisible
        if trigger.frame != triggerFrame { trigger.setFrame(triggerFrame, display: false) }
        if !wasVisible {
            trigger.orderFrontRegardless()
            ownSpace?.add(trigger)
        }
        if logsFrame, !wasVisible || trigger.frame != triggerFrame {
            DataLog.panel.notice("edge trigger \(Self.describe(triggerFrame), privacy: .public) shared edge \(shared ? 1 : 0)")
        }
    }

    /// Resizes the window in one call. The screen-edge side stays glued to the screen edge and the
    /// window grows away from it; vertically it stays at the (clamped) offset, whatever the state.
    func setFrame(for state: PanelWindowState) {
        self.state = state
        applyFrame(reason: "state")
    }

    // MARK: Vertical position

    /// The offset the window shows right now: the live drag or the anchor, clamped to the screen.
    var appliedOffset: CGFloat {
        let offset = dragOffset ?? verticalOffset
        guard let screen = Self.dockScreen else { return offset }
        return placement.clamped(offset: offset, capsuleHeight: capsuleHeight, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// Moves the window to a live drag offset (clamped), no animation, nothing persisted.
    func drag(to offset: CGFloat) {
        dragOffset = offset
        applyFrame(reason: "drag")
    }

    /// Ends a drag: the clamped position the window stands at becomes the anchor. Returns it for persisting.
    @discardableResult
    func endDrag() -> CGFloat {
        let final = appliedOffset
        dragOffset = nil
        verticalOffset = final
        return final
    }

    /// Back to the centred default with a short ease-out move (`Theme.resetPositionDuration`).
    func resetPosition() {
        dragOffset = nil
        animatesFrame = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.resetPositionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            verticalOffset = 0
        }
        animatesFrame = false
    }

    // MARK: Private

    private func applyFrame(reason: StaticString) {
        guard let screen = Self.dockScreen else { return }
        let frame = placement.frame(
            for: state,
            capsuleHeight: capsuleHeight,
            offset: dragOffset ?? verticalOffset,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        if logsFrame {
            DataLog.panel.notice("set \(reason, privacy: .public): \(Self.describe(frame), privacy: .public) screen \(Self.describe(screen.frame), privacy: .public) visible \(Self.describe(screen.visibleFrame), privacy: .public)")
        }
        if animatesFrame {
            animator().setFrame(frame, display: true)
        } else {
            setFrame(frame, display: true)
        }
        if isConcealed { updateEdgeTrigger() }
    }

    /// The primary display (the one carrying the menu bar); falls back to whatever is main.
    private static var dockScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    private static func describe(_ rect: NSRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        if logsFrame {
            let screens = NSScreen.screens.map { Self.describe($0.frame) + " visible " + Self.describe($0.visibleFrame) }.joined(separator: ", ")
            DataLog.panel.notice("screen parameters changed: \(screens, privacy: .public)")
        }
        applyFrame(reason: "screens")
    }

    /// Distributed notifications that cover or uncover the screen: name to (cover kind, covered).
    private static let coverNotifications: [String: (ScreenCover, Bool)] = [
        "com.apple.screensaver.didstart": (.screenSaver, true),
        "com.apple.screensaver.didstop": (.screenSaver, false),
        "com.apple.screenIsLocked": (.lock, true),
        "com.apple.screenIsUnlocked": (.lock, false),
    ]

    private enum ScreenCover { case screenSaver, lock }
    /// What covers the screen right now; the panel is ordered out while this is not empty.
    private var covers: Set<ScreenCover> = []

    @objc private func screenCoverDidChange(_ notification: Notification) {
        guard let (cover, covered) = Self.coverNotifications[notification.name.rawValue] else { return }
        let wasCovered = !covers.isEmpty
        if covered { covers.insert(cover) } else { covers.remove(cover) }
        if logsFrame { DataLog.panel.notice("\(notification.name.rawValue, privacy: .public): covered \(self.covers.count)") }
        if covers.isEmpty, wasCovered {
            if !isHiddenByUser { show() }
        } else if !covers.isEmpty, !wasCovered {
            orderOut(nil)
            updateEdgeTrigger()
        }
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        DataLog.panel.notice("active Space changed to \(StationarySpace.activeSpaceID()): frame \(Self.describe(self.frame), privacy: .public) onActiveSpace \(self.isOnActiveSpace ? 1 : 0) occlusionVisible \(self.occlusionState.contains(.visible) ? 1 : 0)")
    }

    @objc private func windowDidChange(_ notification: Notification) {
        DataLog.panel.notice("\(notification.name.rawValue, privacy: .public): \(Self.describe(self.frame), privacy: .public) occlusionVisible \(self.occlusionState.contains(.visible) ? 1 : 0)")
    }
}
