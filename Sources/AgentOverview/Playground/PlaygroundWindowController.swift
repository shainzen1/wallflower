import AppKit
import SwiftUI

/// The eye playground: a normal titled, resizable window in dark appearance, created lazily
/// and reused. Opened from the menu bar item or with the `--playground` launch argument.
@MainActor
final class PlaygroundWindowController: NSWindowController {
    /// Window size in points; the height is clamped to the screen. The top left corner sits `topLeftInset` from the screen's top left.
    static let contentSize = NSSize(width: 760, height: 1380)
    static let topLeftInset = NSPoint(x: 40, y: 40)

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Eye playground"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PlaygroundView())
        super.init(window: window)
        place(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the window up (the app is an accessory, so it activates itself for this).
    func show() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Fixed position near the top left of the main screen so a screenshot region is predictable.
    /// With the `--retina` launch argument the window opens on the sharpest screen instead.
    private func place(_ window: NSWindow) {
        let preferred = CommandLine.arguments.contains("--retina")
            ? NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor })
            : NSScreen.screens.first
        guard let screen = preferred ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let height = min(Self.contentSize.height, visible.height - Self.topLeftInset.y * 2)
        let frame = NSRect(
            x: screen.frame.minX + Self.topLeftInset.x,
            y: screen.frame.maxY - Self.topLeftInset.y - height,
            width: Self.contentSize.width,
            height: height
        )
        window.setFrame(frame, display: false)
    }
}
