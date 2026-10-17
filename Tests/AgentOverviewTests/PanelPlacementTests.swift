import Foundation
import Testing
@testable import AgentOverview

/// Placement on the screen edge: clamping, frames, the drag threshold, persistence and the model's
/// press and drag handling.
@Suite("Panel placement")
struct PanelPlacementTests {
    /// A 1440 pt tall screen with a 30 pt menu bar and a 60 pt Dock at the bottom.
    private let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
    private let visible = NSRect(x: 0, y: 60, width: 2560, height: 1350)
    private let placement = PanelPlacement(edgeInset: 8)

    // MARK: Clamping

    @Test func offsetInsideTheRoomIsKept() {
        #expect(placement.clamped(offset: 0, capsuleHeight: 140, screenFrame: screen, visibleFrame: visible) == 0)
        #expect(placement.clamped(offset: -200, capsuleHeight: 140, screenFrame: screen, visibleFrame: visible) == -200)
    }

    @Test func offsetStopsBelowTheMenuBar() {
        // Top limit: visible.maxY (1410) - inset (8) - half height (70) - midY (720) = 612.
        #expect(placement.clamped(offset: 5000, capsuleHeight: 140, screenFrame: screen, visibleFrame: visible) == 612)
    }

    @Test func offsetStopsAboveTheDock() {
        // Bottom limit: visible.minY (60) + inset (8) + half height (70) - midY (720) = -582.
        #expect(placement.clamped(offset: -5000, capsuleHeight: 140, screenFrame: screen, visibleFrame: visible) == -582)
    }

    @Test func capsuleTallerThanTheRoomHangsFromTheTop() {
        let height: CGFloat = 1400
        let offset = placement.clamped(offset: -300, capsuleHeight: height, screenFrame: screen, visibleFrame: visible)
        let frame = placement.frame(for: .collapsed, capsuleHeight: height, offset: -300, screenFrame: screen, visibleFrame: visible)
        #expect(offset == CGFloat(1410 - 8 - 700 - 720))
        #expect(frame.maxY == CGFloat(1410 - 8))
    }

    // MARK: Frames

    @Test func defaultFrameIsTheOldCentredPlacement() {
        let frame = placement.frame(for: .collapsed, capsuleHeight: 141, offset: 0, screenFrame: screen, visibleFrame: visible)
        #expect(frame.minY == (screen.midY - 141 / 2).rounded(.down))
        #expect(frame.maxX == screen.maxX)
        #expect(frame.width == Theme.capsuleWidth + Theme.windowPadding)
        #expect(frame.height == 141)
    }

    @Test func expandingGrowsLeftwardOnlyAtAnyOffset() {
        let collapsed = placement.frame(for: .collapsed, capsuleHeight: 140, offset: 300, screenFrame: screen, visibleFrame: visible)
        let expanded = placement.frame(for: .expanded(width: Theme.contentWidth), capsuleHeight: 140, offset: 300, screenFrame: screen, visibleFrame: visible)
        #expect(expanded.maxX == collapsed.maxX)
        #expect(expanded.minY == collapsed.minY)
        #expect(expanded.height == collapsed.height)
        #expect(expanded.width == Theme.contentWidth + Theme.windowPadding)
    }

    @Test func growingCapsuleKeepsItsCentreAtTheAnchor() {
        let small = placement.frame(for: .collapsed, capsuleHeight: 140, offset: 200, screenFrame: screen, visibleFrame: visible)
        let large = placement.frame(for: .collapsed, capsuleHeight: 244, offset: 200, screenFrame: screen, visibleFrame: visible)
        #expect(small.midY == screen.midY + 200)
        #expect(large.midY == screen.midY + 200)
    }

    @Test func growingNearTheTopIsPushedDownAndReturnsWhenItShrinks() {
        let anchor: CGFloat = 600
        let large = placement.frame(for: .collapsed, capsuleHeight: 400, offset: anchor, screenFrame: screen, visibleFrame: visible)
        #expect(large.maxY == visible.maxY - 8)
        let small = placement.frame(for: .collapsed, capsuleHeight: 88, offset: anchor, screenFrame: screen, visibleFrame: visible)
        #expect(small.midY == screen.midY + anchor)
    }

    @Test func screenChangeReclampsTheSameAnchor() {
        let laptop = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let laptopVisible = NSRect(x: 0, y: 0, width: 1512, height: 950)
        let frame = placement.frame(for: .collapsed, capsuleHeight: 140, offset: 600, screenFrame: laptop, visibleFrame: laptopVisible)
        #expect(frame.maxY == CGFloat(950 - 8))
        #expect(frame.maxX == laptop.maxX)
    }

    // MARK: Drag threshold

    @Test func thresholdIsStrict() {
        #expect(!PanelDragTracker.exceedsThreshold(dy: 0, threshold: 4))
        #expect(!PanelDragTracker.exceedsThreshold(dy: 4, threshold: 4))
        #expect(!PanelDragTracker.exceedsThreshold(dy: -4, threshold: 4))
        #expect(PanelDragTracker.exceedsThreshold(dy: 4.5, threshold: 4))
        #expect(PanelDragTracker.exceedsThreshold(dy: -5, threshold: 4))
    }

    @Test func pressStaysAClickBelowTheThreshold() {
        var tracker = PanelDragTracker(startPointerY: 500, startOffset: 10, threshold: 4)
        #expect(tracker.pointerMoved(toY: 503) == nil)
        #expect(tracker.pointerMoved(toY: 496) == nil)
        #expect(!tracker.isDragging)
    }

    @Test func dragFollowsThePointerOneToOneOnceStarted() {
        var tracker = PanelDragTracker(startPointerY: 500, startOffset: 10, threshold: 4)
        #expect(tracker.pointerMoved(toY: 505) == 15)
        #expect(tracker.isDragging)
        // Back inside the threshold band: still a drag, still 1:1.
        #expect(tracker.pointerMoved(toY: 502) == 12)
        #expect(tracker.pointerMoved(toY: 380) == -110)
    }

    // MARK: Persistence

    @Test func offsetRoundTripsThroughDefaults() throws {
        let suite = "agent-overview-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PanelPositionStore(defaults: defaults)
        #expect(store.load() == nil)
        store.save(-123.5)
        #expect(defaults.double(forKey: PanelPositionStore.key) == -123.5)
        #expect(PanelPositionStore(defaults: defaults).load() == -123.5)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func unreadableStoredValueMeansDefault() throws {
        let suite = "agent-overview-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("up", forKey: PanelPositionStore.key)
        #expect(PanelPositionStore(defaults: defaults).load() == nil)
    }

    // MARK: Launch argument

    @Test func verticalOffsetArgumentParses() {
        #expect(LaunchArguments(["app", "--vertical-offset", "-240"]).verticalOffset == -240)
        #expect(LaunchArguments(["app", "--vertical-offset", "nope"]).verticalOffset == nil)
        #expect(LaunchArguments(["app", "--log-frame"]).logFrame)
    }
}

@Suite("Panel drag in the model")
@MainActor
struct PanelDragModelTests {
    /// A store with one live desktop session (synthetic fixture) and its model.
    private func makeModel() throws -> (SessionStore, PanelModel) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var record = try TestSupport.fixtureRecord("idle-desktop")
        record.pid = TestSupport.livePid
        store.reconcile(RegistryScanResult(records: [record], presentPids: [record.pid]))
        return (store, PanelModel(store: store))
    }

    @Test func releaseOfADragOpensNothingAndTheNextClickDoes() throws {
        let (store, model) = try makeModel()
        defer { store.stop() }
        let row = try #require(model.rows.first)
        var opened = 0
        model.open = { _ in opened += 1 }

        model.pressBegan()
        model.tapped(row)
        #expect(opened == 1, "a plain click opens")

        model.pressBegan()
        model.dragBegan()
        model.dragEnded()
        model.tapped(row)
        #expect(opened == 1, "the release of a drag opens nothing")

        model.pressBegan()
        model.tapped(row)
        #expect(opened == 2, "the next press clicks again")
    }

    @Test func pointerReportsAreFrozenWhileDragging() throws {
        let (store, model) = try makeModel()
        defer { store.stop() }
        let width = Theme.capsuleWidth + Theme.bulgeMaxWidth + Theme.windowPadding
        let size = CGSize(width: width, height: model.capsuleHeight)
        let onFace = CGPoint(x: width - Theme.capsuleWidth / 2, y: PanelModel.rowCenterY(index: 0))

        model.pointerMoved(to: onFace, in: size)
        #expect(model.hoveredRowIndex == 0)

        model.pressBegan()
        model.dragBegan()
        model.pointerMoved(to: nil, in: size)
        model.pointerMoved(to: CGPoint(x: 0, y: 0), in: size)
        #expect(model.hoveredRowIndex == 0, "the hover stays put while the window moves")
        #expect(model.isExpanded)

        model.dragEnded()
        model.pointerMoved(to: nil, in: size)
        #expect(!model.isExpanded, "reports flow again after the drag")
    }
}
