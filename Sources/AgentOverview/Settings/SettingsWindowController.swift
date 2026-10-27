import AppKit
import SwiftUI

/// The Settings window: the classic macOS preferences look, a toolbar with one item per tab
/// (General, Appearance, Sound, Agents, About), the window title following the tab, not resizable, its height
/// animating to fit each tab up to `maxContentHeight`, past which the tab scrolls. Each tab is a SwiftUI
/// grouped `Form` in an `NSHostingController`.
/// Created on demand and released when closed (`onClose`).
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Width of every tab, in points.
    static let width: CGFloat = 520
    /// Tallest a tab's content may make the window, in points; a taller tab scrolls. With the title bar
    /// and toolbar (about 90 pt) the window stays under 740 pt, which fits a 13-inch MacBook at its
    /// default scaling (1440 x 900 and 1470 x 956, minus the menu bar and the Dock). General (about
    /// 870 pt with one action) and Agents (about 1100 pt with seven agents found) used to run off it.
    static let maxContentHeight: CGFloat = 640
    /// Space kept free above and below the window on a screen too short even for `maxContentHeight`.
    static let screenMargin: CGFloat = 20

    /// Called once the window closed; the owner drops its reference so the content is released.
    var onClose: (() -> Void)?

    private let tabs: SettingsTabViewController
    private let launchAtLogin: LaunchAtLogin
    private let accessibility: AccessibilityAccess
    /// The General tab's actions editor (nil without an action store).
    let actionEditor: ActionEditorModel?
    /// The Agents tab's state. Without one (tests), an empty home where nothing is found.
    let agents: AgentsModel

    /// - Parameters:
    ///   - actionStore: the action faces, for the actions editor on the General tab.
    ///   - showsAdvanced: open the Appearance tab's Advanced disclosure (`--settings-advanced`).
    init(
        settings: AppSettings, launchAtLogin: LaunchAtLogin, updater: AppUpdater? = nil, actions: SettingsActions, actionStore: ActionStore? = nil,
        agents: AgentsModel? = nil, sounds: SoundController? = nil, tab: SettingsTab = .general, showsAdvanced: Bool = false
    ) {
        let accessibility = AccessibilityAccess()
        let actionEditor = actionStore.map { ActionEditorModel(store: $0) }
        self.launchAtLogin = launchAtLogin
        self.accessibility = accessibility
        self.actionEditor = actionEditor
        let agents = agents ?? AgentsModel(environment: .fixture(home: URL(filePath: "/nonexistent", directoryHint: .isDirectory)), settings: settings)
        self.agents = agents
        tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        tabs.addTab(SettingsTab.general, content: GeneralSettingsView(
            settings: settings, launchAtLogin: launchAtLogin, updater: updater, accessibility: accessibility, actions: actions,
            actionEditor: actionEditor
        ))
        tabs.addTab(SettingsTab.appearance, content: AppearanceSettingsView(
            settings: settings, actions: actions, state: AppearanceViewState(showsAdvanced: showsAdvanced)
        ))
        // Without a controller (tests), one whose folder does not exist: nothing is written unless a file is chosen.
        let sounds = sounds ?? SoundController(settings: settings, folder: URL(filePath: "/nonexistent/Sounds", directoryHint: .isDirectory))
        tabs.addTab(SettingsTab.sound, content: SoundSettingsView(settings: settings, sounds: sounds, state: SoundViewState()))
        tabs.addTab(SettingsTab.agents, content: AgentsSettingsView(model: agents, settings: settings))
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
        // Back from System Settings: show what changed there. Back from an editor: the agents' files.
        launchAtLogin.refresh()
        accessibility.refresh()
        if selectedTab == .agents { agents.refresh() }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // A shorter screen may need a lower cap (`SettingsTabViewController.maxContentHeight(in:)`).
        tabs.fitWindow(animated: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// The toolbar-style tab controller. It animates the window to the selected tab's height (the top
/// edge stays put) on a tab switch and whenever the tab's content changes height (the Advanced
/// disclosure, an inline note), so no tab shows empty space. A tab taller than
/// `SettingsWindowController.maxContentHeight` (or than the screen allows) scrolls instead.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private var sizeObservations: [NSKeyValueObservation] = []
    /// The tallest a tab may be on this window's screen, read by every tab's root view.
    private let cap = SettingsContentCap()

    /// Adds one tab: its SwiftUI content in a hosting controller that reports its ideal size.
    func addTab<Content: View>(_ tab: SettingsTab, content: Content) {
        let root = SettingsTabRoot(cap: cap, content: content)
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

    /// Sizes the window to the selected tab's preferred content size, at most `maxContentHeight(in:)`,
    /// keeping its top edge.
    func fitWindow(animated: Bool) {
        guard let window = view.window, let content = selectedViewController else { return }
        // A new cap changes the tabs' preferred sizes, which calls this again through the observation.
        let maxHeight = Self.maxContentHeight(in: window)
        if cap.height != maxHeight { cap.height = maxHeight }
        var size = content.preferredContentSize
        if size.height < 1 { size = content.view.fittingSize }
        size.width = SettingsWindowController.width
        size.height = min(size.height, maxHeight)
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

    /// `SettingsWindowController.maxContentHeight`, or less on a screen whose visible height (without
    /// the menu bar and the Dock) cannot hold that, the title bar and toolbar, and a margin top and bottom.
    static func maxContentHeight(in window: NSWindow) -> CGFloat {
        guard let screen = window.screen ?? NSScreen.main else { return SettingsWindowController.maxContentHeight }
        let chrome = window.frame.height - window.contentLayoutRect.height
        return maxContentHeight(visibleScreenHeight: screen.visibleFrame.height, chrome: chrome)
    }

    /// The cap for a screen of that visible height and a window with that much title bar and toolbar.
    static func maxContentHeight(visibleScreenHeight: CGFloat, chrome: CGFloat) -> CGFloat {
        let fits = visibleScreenHeight - chrome - 2 * SettingsWindowController.screenMargin
        return max(min(SettingsWindowController.maxContentHeight, fits), 200)
    }
}

/// The tallest a Settings tab may be (`SettingsTabViewController.maxContentHeight(in:)`), shared by the tabs.
@MainActor @Observable
final class SettingsContentCap {
    var height = SettingsWindowController.maxContentHeight
}

/// One tab's root: the form at its full ideal height in a scroll view, capped at `cap.height`. The
/// scroll view's ideal height is the form's, so the hosting controller reports the form's height up to
/// the cap and the window fits it; past the cap the scroll view scrolls. The forms keep
/// `scrollDisabled(true)`, so only this one scrolls, and it does not bounce when everything fits. The
/// cap is in the view (not only in `fitWindow`): the tab view controller also sizes the window to the
/// preferred size on a tab switch.
private struct SettingsTabRoot<Content: View>: View {
    let cap: SettingsContentCap
    let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(width: SettingsWindowController.width)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: SettingsWindowController.width)
        .frame(maxHeight: cap.height, alignment: .top)
    }
}
