import AppKit

/// Layer-hosting NSView that owns one `EyeLayerTree`. It draws nothing itself; everything
/// is Core Animation, so the view never redraws and the app never wakes for a frame.
@MainActor
final class EyesHostView: NSView {
    private var tree: EyeLayerTree!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        tree = EyeLayerTree(root: root)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reduceMotionDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The throw pose last applied: a changed pose animates with its motion, an unchanged one is set at once.
    private var appliedThrow = FaceThrowPose.rest

    func apply(_ configuration: FaceConfiguration) {
        tree.apply(configuration)
        configuration.throwPose.apply(leave: configuration.leave, to: layer!, previous: appliedThrow)
        appliedThrow = configuration.throwPose
    }

    /// The panel never becomes key; a click on a face must count the first time.
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
        tree.setScale(scale)
    }

    @objc private func reduceMotionDidChange(_ notification: Notification) {
        tree.reduceMotionDidChange()
    }
}
