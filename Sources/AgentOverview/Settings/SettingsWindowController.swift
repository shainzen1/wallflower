import AppKit
import SwiftUI

/// The Settings window: the classic macOS preferences look, a toolbar with one item per tab
/// (General, Appearance, About), the window title following the tab, not resizable, its height
/// animating to fit each tab. Each tab is a SwiftUI grouped `Form` in an `NSHostingController`.
/// Created on demand and released when closed (`onClose`).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Width of every tab, in points.
    static let width: CGFloat = 520

    /// Called once the window closed; the owner drops its reference so the content is released.
    var onClose: (() -> Void)?

    private let tabs: SettingsTabViewController
    private let launchAtLogin: LaunchAtLogin
    private let accessibility: AccessibilityAccess
    /// The General tab's actions editor (nil without an action store).
    let actionEditor: ActionEditorModel?

    /// - Parameters:
    ///   - actionStore: the action faces, for the actions editor on the General tab.
    ///   - showsAdvanced: open the Appearance tab's Advanced disclosure (`--settings-advanced`).
    init(
        settings: AppSettings, launchAtLogin: LaunchAtLogin, actions: SettingsActions, actionStore: ActionStore? = nil,
        tab: SettingsTab = .general, showsAdvanced: Bool = false
    ) {
        let accessibility = AccessibilityAccess()
        let actionEditor = actionStore.map { ActionEditorModel(store: $0) }
        self.launchAtLogin = launchAtLogin
        self.accessibility = accessibility
        self.actionEditor = actionEditor
        tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        tabs.addTab(SettingsTab.general, content: GeneralSettingsView(
            settings: settings, launchAtLogin: launchAtLogin, accessibility: accessibility, actions: actions,
            actionEditor: actionEditor
        ))
        tabs.addTab(SettingsTab.appearance, content: AppearanceSettingsView(
            settings: settings, actions: actions, state: AppearanceViewState(showsAdvanced: showsAdvanced)
        ))
        tabs.addTab(SettingsTab.about, content: AboutSettingsView(actions: actions))
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.contentViewController = tabs
        window.title = tab.title
        // Remembers where the person put it; centred the first time.
        window.setFrameAutosaveName("\(AppInfo.name) Settings")
        super.init(window: window)
        window.delegate = self
        tabs.fitWindow(animated: false)
        if !window.setFrameUsingName(window.frameAutosaveName) { window.center() }
        tabs.fitWindow(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The tab on screen.
    var selectedTab: SettingsTab {
        SettingsTab.allCases[max(tabs.selectedTabViewItemIndex, 0)]
    }

    /// Brings the window to the front on `tab` (or the tab it shows) and activates the app, which is
    /// an accessory and would otherwise leave the window behind the frontmost app.
    func show(tab: SettingsTab? = nil) {
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab), index != tabs.selectedTabViewItemIndex {
            tabs.selectedTabViewItemIndex = index
        }
        launchAtLogin.refresh()
        accessibility.refresh()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Back from System Settings: show what changed there.
        launchAtLogin.refresh()
        accessibility.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// The toolbar-style tab controller. It animates the window to the selected tab's height (the top
/// edge stays put) on a tab switch and whenever the tab's content changes height (the Advanced
/// disclosure, an inline note), so no tab ever scrolls or shows empty space.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private var sizeObservations: [NSKeyValueObservation] = []

    /// Adds one tab: its SwiftUI content in a hosting controller that reports its ideal size.
    func addTab<Content: View>(_ tab: SettingsTab, content: Content) {
        // Ideal height reported to the window; pinned to the top while the window animates to it.
        let root = content
            .frame(width: SettingsWindowController.width)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = tab.title
        let item = NSTabViewItem(viewController: hosting)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
        addTabViewItem(item)
        observeSize(of: hosting)
    }

    /// Refits the window whenever `controller` reports a new preferred size while its tab is selected.
    /// Not generic: a KVO handler formed inside `addTab` would capture the `Content` metatype.
    private func observeSize(of controller: NSViewController) {
        sizeObservations.append(controller.observe(\.preferredContentSize, options: [.new]) { [weak self, weak controller] _, _ in
            MainActor.assumeIsolated {
                guard let self, let controller, self.selectedViewController === controller else { return }
                self.fitWindow(animated: true)
            }
        })
    }

    private var selectedViewController: NSViewController? {
        let index = selectedTabViewItemIndex
        guard tabViewItems.indices.contains(index) else { return nil }
        return tabViewItems[index].viewController
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: view.window?.isVisible == true)
    }

    /// Sizes the window to the selected tab's preferred content size, keeping its top edge.
    func fitWindow(animated: Bool) {
        guard let window = view.window, let content = selectedViewController else { return }
        var size = content.preferredContentSize
        if size.height < 1 { size = content.view.fittingSize }
        size.width = SettingsWindowController.width
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        guard abs(frame.height - target.height) > 0.5 || abs(frame.width - target.width) > 0.5 else { return }
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}
