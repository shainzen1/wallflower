import AppKit
import SwiftUI

/// The welcome window: shown on first launch once the panel is up, and again from the menu or
/// About. Dark and pure black, the content under a transparent, hidden titlebar, only the close
/// button kept, centred, fixed size. Esc, ⌘W and the close button dismiss it; that counts as done.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    let model: WelcomeModel
    /// Called once the window closed; the owner drops its reference so the content is released.
    var onClose: (() -> Void)?

    init(model: WelcomeModel, look: PanelLook) {
        self.model = model
        let window = WelcomeWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeStyle.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to \(AppInfo.name)"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        let hosting = NSHostingView(rootView: WelcomeView(model: model, look: look))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: WelcomeStyle.size)
        window.contentView = hosting
        window.setContentSize(WelcomeStyle.size)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in self?.close() }
        model.onRequestClose = { [weak self] in self?.close() }
        model.onPageWillChange = { [weak hosting] in
            guard let hosting else { return }
            Self.fadeOut(faceViews(in: hosting))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the window up and activates the app (an accessory would leave it behind the frontmost app).
    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // A close without "Start" (Esc, ⌘W, the close button) is a dismissal; after "Start" it is a no-op.
        model.finish(.dismissed)
        onClose?()
    }
}

extension WelcomeWindowController {
    /// How long the leaving page's faces take to fade, a little quicker than the page's own fade.
    static let faceFadeDuration: TimeInterval = 0.18

    /// Fades the leaving page's faces (their host views' alpha, the one opacity AppKit owns).
    static func fadeOut(_ faces: [NSView]) {
        guard !faces.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = faceFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for face in faces { face.animator().alphaValue = 0 }
        }
    }
}

/// The face host views (blob and dot-matrix eyes) under `view`.
@MainActor
private func faceViews(in view: NSView) -> [NSView] {
    view.subviews.flatMap { subview -> [NSView] in
        subview is BlobHostView || subview is EyesHostView ? [subview] : faceViews(in: subview)
    }
}

/// The welcome's window: Esc closes it.
final class WelcomeWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
