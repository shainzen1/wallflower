import AppKit
import SwiftUI
import Testing
@testable import AgentOverview

/// The "Set up" page's card holds its controls: the segmented control spans the card's content and
/// the switch sits inside the right inset, laid out in a real hosting view at the window's size.
@Suite("Welcome: the Set up card contains its controls")
@MainActor
struct WelcomeLayoutTests {
    /// The page laid out in a window of the welcome's size, and every view in it.
    private func layOut(_ source: SessionSource) -> (NSView, [NSView], WelcomeModel) {
        let model = WelcomeModel(page: 4, sessionSource: source)
        let hosting = NSHostingView(rootView: WelcomeView(model: model, look: .themeDefault))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: WelcomeStyle.size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        var views: [NSView] = []
        func walk(_ view: NSView) {
            views.append(view)
            view.subviews.forEach(walk)
        }
        walk(hosting)
        return (hosting, views, model)
    }

    @Test("The segmented control spans the card's content and the switch keeps the 16 pt inset", arguments: SessionSource.allCases)
    func cardContainsControls(source: SessionSource) throws {
        let (hosting, views, model) = layOut(source)
        let cardMinX = (WelcomeStyle.size.width - WelcomeStyle.setUpCardWidth) / 2
        let inner = (cardMinX + WelcomeStyle.setUpInset)...(cardMinX + WelcomeStyle.setUpCardWidth - WelcomeStyle.setUpInset)
        let segmented = try #require(views.compactMap { $0 as? NSSegmentedControl }.first)
        let frame = segmented.convert(segmented.bounds, to: hosting)
        #expect(abs(frame.minX - inner.lowerBound) < 0.5 && abs(frame.maxX - inner.upperBound) < 0.5, "spans the content: \(frame)")
        #expect(segmented.intrinsicContentSize.width <= WelcomeStyle.setUpContentWidth, "its labels fit the card (\(segmented.intrinsicContentSize.width))")
        #expect(segmented.segmentCount == 3 && (0..<3).map { segmented.label(forSegment: $0) } == ["Claude app", "Terminal", "Everywhere"])
        #expect(segmented.selectedSegment == SessionSource.allCases.firstIndex(of: model.sessionSource))
        let toggle = try #require(views.first { $0 is NSSwitch || String(describing: type(of: $0)).contains("PlatformSwitch") })
        let toggleFrame = toggle.convert(toggle.bounds, to: hosting)
        #expect(toggleFrame.minX >= inner.lowerBound && abs(toggleFrame.maxX - inner.upperBound) < 0.5, "inside the right inset: \(toggleFrame)")
    }

    @Test("Choosing a segment sets the session source")
    func selection() throws {
        let (_, views, model) = layOut(.desktop)
        let segmented = try #require(views.compactMap { $0 as? NSSegmentedControl }.first)
        segmented.selectedSegment = 2
        _ = segmented.target?.perform(segmented.action, with: segmented)
        #expect(model.sessionSource == .everywhere)
        #expect(SessionSource.terminal.title == "Terminal & editors", "Settings keeps the long label")
    }
}
