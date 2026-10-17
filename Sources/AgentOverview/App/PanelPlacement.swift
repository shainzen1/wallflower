import Foundation

/// Where the panel sits on its screen edge: pure geometry, no AppKit state, so it is testable.
/// `side` picks the edge (`PanelSide`): the window is flush with the screen's right edge, or its left.
///
/// The vertical position is an offset of the window's centre from the screen's vertical centre
/// (positive is up, AppKit coordinates). The offset is clamped so the window stays inside the
/// screen's `visibleFrame` (never under the menu bar or the Dock) with `edgeInset` to spare at the
/// top and the bottom. A capsule taller than that room hangs from the top limit, so the first rows
/// (needs input sorts first) stay visible.
struct PanelPlacement: Equatable, Sendable {
    /// Room kept to the top and the bottom of the visible frame.
    var edgeInset: CGFloat = Theme.dockEdgeInset
    /// The screen edge the window is flush with.
    var side: PanelSide = .default

    /// Window width for a geometry state: the capsule (or the expanded shape) plus the padding.
    static func width(for state: PanelWindowState) -> CGFloat {
        switch state {
        case .collapsed: Theme.capsuleWidth + Theme.windowPadding
        case .expanded(let capsuleWidth): capsuleWidth + Theme.windowPadding
        }
    }

    /// The offset the window can actually take for a capsule of `capsuleHeight`: `offset` limited to
    /// the visible frame minus the insets. Too tall for the room: the offset that hangs it from the top limit.
    func clamped(offset: CGFloat, capsuleHeight: CGFloat, screenFrame: NSRect, visibleFrame: NSRect) -> CGFloat {
        let halfHeight = capsuleHeight / 2
        let lowest = visibleFrame.minY + edgeInset + halfHeight - screenFrame.midY
        let highest = visibleFrame.maxY - edgeInset - halfHeight - screenFrame.midY
        guard lowest <= highest else { return highest }
        return min(max(offset, lowest), highest)
    }

    /// The window frame: flush with the screen edge of `side` (the right edge at the screen's maxX,
    /// growing leftward; the left edge at its minX, growing rightward), width from the state, the
    /// centre at the clamped offset from the screen's vertical centre (origin rounded down to whole points).
    func frame(for state: PanelWindowState, capsuleHeight: CGFloat, offset: CGFloat, screenFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let width = Self.width(for: state)
        let applied = clamped(offset: offset, capsuleHeight: capsuleHeight, screenFrame: screenFrame, visibleFrame: visibleFrame)
        return NSRect(
            x: side.isMirrored ? screenFrame.minX : screenFrame.maxX - width,
            y: (screenFrame.midY + applied - capsuleHeight / 2).rounded(.down),
            width: width,
            height: capsuleHeight
        )
    }
}

/// A press on the panel, deciding between a click and a drag along the edge.
/// The press stays a click until the pointer moved more than `threshold` vertically; from then on
/// the window follows the pointer 1:1 (the offset moves exactly as far as the pointer did since the press).
struct PanelDragTracker: Equatable, Sendable {
    /// Pointer height at the press, in screen coordinates (y up).
    let startPointerY: CGFloat
    /// Window offset at the press (the clamped one the window actually had).
    let startOffset: CGFloat
    /// Vertical travel that turns the press into a drag.
    let threshold: CGFloat
    /// True once the press became a drag; it stays a drag until the release.
    private(set) var isDragging = false

    init(startPointerY: CGFloat, startOffset: CGFloat, threshold: CGFloat = Theme.dragThreshold) {
        self.startPointerY = startPointerY
        self.startOffset = startOffset
        self.threshold = threshold
    }

    /// Whether a vertical travel of `dy` turns a press into a drag (strictly more than the threshold).
    static func exceedsThreshold(dy: CGFloat, threshold: CGFloat = Theme.dragThreshold) -> Bool {
        abs(dy) > threshold
    }

    /// Feeds a pointer height. Returns the unclamped window offset once the press is a drag, nil while it is still a click.
    mutating func pointerMoved(toY y: CGFloat) -> CGFloat? {
        let dy = y - startPointerY
        if !isDragging {
            guard Self.exceedsThreshold(dy: dy, threshold: threshold) else { return nil }
            isDragging = true
        }
        return startOffset + dy
    }
}

/// The persisted vertical offset of the panel (`panelVerticalOffset` in the given defaults).
/// Nothing stored means the default, centred placement.
struct PanelPositionStore: @unchecked Sendable {
    /// Defaults key of the offset (points from the screen's vertical centre, positive is up).
    static let key = "panelVerticalOffset"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored offset, nil when the panel was never moved (or was reset).
    func load() -> CGFloat? {
        guard let value = defaults.object(forKey: Self.key) as? Double, value.isFinite else { return nil }
        return CGFloat(value)
    }

    func save(_ offset: CGFloat) {
        defaults.set(Double(offset), forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
