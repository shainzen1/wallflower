import Observation
import SwiftUI

/// UI state of the panel and the bridge between the stores and the capsule.
/// `rows` is computed from the session store on every read so `@Observable` tracking reaches the
/// `Session` objects; nothing is copied. `actionRows` comes from the `ActionStore` the same way.
/// Owned by `AppDelegate` for the life of the process.
///
/// Slots: the capsule stacks the new session button (when shown) and its divider, the live rows,
/// then (with both present) the divider, then the action rows. A slot index counts rows first and
/// actions after them (`rows.count + actionIndex`); the button is `newSessionSlot` (-1), so the row
/// and action indices are the same with or without it. The dividers have no slot, they are gaps in
/// the geometry that `rowIndex(atY:)` snaps across.
///
/// Hover: the hosting view reports pointer positions, the model turns them into `hoveredKey` or
/// `hoveredActionID` and `isExpanded` and sequences the window geometry (animation rule 4): the
/// window grows to the expanded width the moment a hover begins, and shrinks back
/// `Theme.closeSpringSettleTime` after the hover ended, unless the pointer came back in the meantime.
///
/// Magnification (`.magnify` hover effect): the model also keeps the pointer itself (`pointer`, in
/// capsule coordinates) and derives one `MagnifyState` per slot from it (`magnify(slot:)`),
/// read by each face's `MagnifiedFaceView` alone, so a pointer move re-evaluates nothing but those.
///
/// Throw (`PanelDragController` decides the press is one, `FaceThrow` holds the geometry): while the
/// pointer holds a face, `throwingKey` closes the bulge and freezes the hover, and `throwPose` moves
/// that face alone. A throw out flies the face away, then hides the session (`HiddenSessions`):
/// `rows` and the capsule size skip hidden sessions, so the row departs as any other.
@Observable @MainActor
final class PanelModel {
    let store: SessionStore
    /// The action faces below the divider; nil means no action section at all.
    let actionStore: ActionStore?
    /// Sessions thrown out of the capsule (not watched); nil means faces cannot be thrown.
    let hiddenSessions: HiddenSessions?
    /// Session row under the pointer (the goo bulge follows it). Nil at rest or on an action row.
    private(set) var hoveredKey: SessionKey?
    /// Action row under the pointer. Nil at rest or on a session row.
    private(set) var hoveredActionID: String?
    /// True while the capsule is expanded (a bulge is open, or the whole capsule in `.all` mode).
    /// Only then does the time-in-state text exist and tick.
    private(set) var isExpanded = false
    /// Slot the bulge sits at. Kept after the hover ended so the bulge melts in place instead of travelling.
    private(set) var bulgeRowIndex = 0
    /// True while the last goo change was a close (bulge melting, rows leaving): the close spring applies.
    private(set) var gooClosing = false
    /// True when the current hover moved the bulge from another slot (the reveal waits for the travel).
    private(set) var bulgeTravelled = false
    /// Hover behaviour: `Theme.expandMode`, or the `--expand` launch argument.
    let expandMode: Theme.ExpandMode
    /// Goo renderer: `Theme.gooRenderer`, or the `--goo` launch argument.
    let gooRenderer: Theme.GooRenderer
    /// Hover effect: `Theme.hoverEffect`, or the `--hover-effect` launch argument.
    let hoverEffect: Theme.HoverEffect
    /// Whether the new session button shows at the top of the column (Settings > General).
    let showsNewSession: Bool
    /// Which sessions the panel shows; it picks the new session button's route.
    let sessionSource: SessionSource
    /// The screen edge the panel docks to: the rows put the face on that side and the bulge on the
    /// other, the goo and the edge cue are drawn mirrored on the left, and pointer positions are
    /// measured from that edge.
    let side: PanelSide
    /// The new session button is under the pointer.
    private(set) var hoveredNewSession = false
    /// Click counter of the new session button: its ring dips once per bump.
    private(set) var newSessionClickToken = 0
    /// The pointer in capsule coordinates (x from the capsule's left edge on screen, whichever side
    /// it docks to; y from its top, fillet included) while it is on the capsule or the open bulge;
    /// nil otherwise. Drives the magnification, which therefore needs no mirroring: a face leans
    /// toward the real pointer.
    private(set) var pointer: CGPoint?

    /// Opens the chat of a row. Replaceable so launch checks and tests can observe clicks.
    @ObservationIgnored var open: @MainActor (SessionRow) -> Void = SessionOpener.open
    /// Starts an action's session and reports whether the prompt was sent. Replaceable so tests can
    /// observe clicks without launching anything.
    @ObservationIgnored var runAction: @MainActor (ActionItem, @escaping @MainActor (ActionLaunch.Report) -> Void) -> Void = {
        ActionLaunch.run($0, report: $1)
    }
    /// Starts a new session on a route. Replaceable so tests can observe clicks without launching anything.
    @ObservationIgnored var startNewSession: @MainActor (NewSessionLaunch.Route) -> Void = { NewSessionLaunch.run($0) }
    /// How long the "Press Return in Claude" hint stays (`Theme.actionSendHintDuration`; tests shorten it).
    @ObservationIgnored var sendHintDuration: TimeInterval = Theme.actionSendHintDuration
    /// Receives the window's capsule height: immediately when the capsule grows, after the
    /// close spring settled when it shrinks. `AppDelegate` wires it to the panel window.
    @ObservationIgnored var setWindowHeight: (@MainActor (CGFloat) -> Void)?
    /// Receives the window geometry state: `.expanded` the moment a hover begins, `.collapsed`
    /// once the close spring settled after the hover ended. `AppDelegate` wires it to the panel window.
    @ObservationIgnored var setWindowState: (@MainActor (PanelWindowState) -> Void)?

    /// Hop tokens per session: bumped when a session enters needs input (`AttentionTracker` rule).
    /// Observed, so the row re-renders and its face hops; the rule's memory itself is not observed.
    private(set) var attentionTokens: [SessionKey: Int] = [:]
    @ObservationIgnored private var attention = AttentionTracker()
    /// Excited tokens per session: bumped when a resting or waiting session starts working (the
    /// person's message arrived, `ExcitedTracker` rule). Observed, so the row's face perks up once.
    private(set) var excitedTokens: [SessionKey: Int] = [:]
    @ObservationIgnored private var excited = ExcitedTracker()
    /// When the person last opened each session's chat: an idle period acknowledged this way is no
    /// longer your turn (`IdleTier`). Observed, so the clicked row drops to idle and re-sorts.
    private(set) var acknowledgements = Acknowledgements()
    /// The clock of the tier rule (tests replace it).
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    /// Actions whose click feedback (the working cloud) is showing.
    private(set) var launchingActionIDs: Set<String> = []
    /// Click counters per action: the face squints once per bump.
    private(set) var squintTokens: [String: Int] = [:]
    /// Actions whose prompt could only be prefilled: their bulge shows `Theme.actionSendHint`.
    private(set) var sendHintActionIDs: Set<String> = []

    /// True while the person drags the panel along the screen edge: pointer reports are frozen, so the
    /// hover stays where the press began (the pointer rides along with the window anyway, and at the
    /// clamp limits it would otherwise slide over other rows or out of the window).
    @ObservationIgnored private(set) var isDraggingPanel = false
    /// True from the moment a press became a drag until the next press: the release of a drag must
    /// not open anything, whatever the row's button makes of it.
    @ObservationIgnored private var swallowsTap = false

    /// The session whose face the pointer holds (a throw in progress): the bulge is closed, pointer
    /// reports are frozen and only that face moves. Nil otherwise.
    private(set) var throwingKey: SessionKey?
    /// Where the held face is drawn (read only by that face, `throwPose(for:)`).
    private(set) var throwPose = FaceThrowPose.rest
    /// Faces thrown out: their fly-away pose, kept while the row departs (and until the session is
    /// shown again or leaves the registry), so a departing face never reappears.
    private(set) var flownPoses: [SessionKey: FaceThrowPose] = [:]
    /// The face let go short of a throw, still springing back into its slot: it keeps drawing on top.
    private(set) var returningKey: SessionKey?
    /// Reduce Motion at the moment of the throw (tests replace it).
    @ObservationIgnored var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// How long a thrown face flies before its session is hidden (`Theme.throwFlyDuration`; tests shorten it).
    @ObservationIgnored var throwFlyDuration: TimeInterval = Theme.throwFlyDuration
    @ObservationIgnored private var flyTasks: [SessionKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var returnTask: Task<Void, Never>?

    @ObservationIgnored private var lastCapsuleHeight: CGFloat?
    /// The stack ids (`CapsuleView`'s `ids`) of the last layout, nil before the first one: what is
    /// new in the next layout arrives (its slot opens, its face pops, `RowEntrance`).
    @ObservationIgnored private var shownStackIDs: [String]?
    @ObservationIgnored private var pendingShrink: Task<Void, Never>?
    @ObservationIgnored private var pendingCollapse: Task<Void, Never>?
    @ObservationIgnored private var launchTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var hintTasks: [String: Task<Void, Never>] = [:]

    init(
        store: SessionStore, actionStore: ActionStore? = nil, hiddenSessions: HiddenSessions? = nil,
        expandMode: Theme.ExpandMode = Theme.expandMode,
        gooRenderer: Theme.GooRenderer = Theme.gooRenderer, hoverEffect: Theme.HoverEffect = Theme.hoverEffect,
        newSessionButton: Bool = false, sessionSource: SessionSource = .desktop, side: PanelSide = .default
    ) {
        self.showsNewSession = newSessionButton
        self.sessionSource = sessionSource
        self.side = side
        self.store = store
        self.actionStore = actionStore
        self.hiddenSessions = hiddenSessions
        self.expandMode = expandMode
        self.gooRenderer = gooRenderer
        self.hoverEffect = hoverEffect
        if hiddenSessions != nil { observeSessionsForPruning() }
    }

    /// The store's sessions less the hidden ones. A hidden session stays hidden whatever it does
    /// (waiting for input included): the person chose to stop watching it. In the store's order
    /// (needs input, working, your turn, idle), re-sorted with the acknowledgements once there are
    /// any: without them the store's order already is the tier order (within idle the newest idle
    /// start comes first, and the your-turn window is the same length for every session).
    var visibleSessions: [Session] {
        var sessions = store.sessions
        if let hiddenSessions, hiddenSessions.count > 0 {
            sessions = sessions.filter { !hiddenSessions.contains($0) }
        }
        guard !acknowledgements.isEmpty else { return sessions }
        return SessionStore.sorted(sessions, acknowledgements: acknowledgements.times, now: now())
    }

    /// One row per visible session, in the panel's order (needs input, working, your turn, idle). With
    /// `--demo-states` the first two rows are forced into the demo looks (delegating with satellites, then coding).
    var rows: [SessionRow] {
        let date = now()
        var rows = visibleSessions.map { SessionRow(session: $0, now: date, acknowledgedAt: acknowledgements.time(for: $0.key)) }
        if RowDemo.enabled {
            if !rows.isEmpty { rows[0] = rows[0].demo() }
            if rows.count > 1 {
                rows[1] = rows[1].demo(activity: RowDemo.secondActivity, subagentCount: RowDemo.secondSubagentCount, projectKey: RowDemo.secondProjectKey)
            }
        }
        return rows
    }

    /// One row per action shown today (`ActionStore.visibleActions`), in file order.
    var actionRows: [ActionRow] {
        (actionStore?.visibleActions ?? []).map { item in
            ActionRow(
                item: item, launching: launchingActionIDs.contains(item.id), squintToken: squintTokens[item.id] ?? 0,
                hint: sendHintActionIDs.contains(item.id) ? Theme.actionSendHint : nil
            )
        }
    }

    /// Session rows plus action rows: the number of hoverable slots besides the new session button.
    var slotCount: Int { rows.count + actionRows.count }

    /// The slot of the new session button: above every row, outside the row and action indices.
    nonisolated static let newSessionSlot = -1

    /// Whether `slot` is a slot of the current layout (the new session button's only while it shows).
    func containsSlot(_ slot: Int) -> Bool {
        slot == Self.newSessionSlot ? showsNewSession : slot >= 0 && slot < slotCount
    }

    /// Where the new session button opens a session.
    var newSessionRoute: NewSessionLaunch.Route {
        NewSessionLaunch.route(for: sessionSource)
    }

    // MARK: Attention hop

    /// The hop token of a row's face (0 until the session first entered needs input while shown).
    func attentionToken(for key: SessionKey) -> Int {
        attentionTokens[key] ?? 0
    }

    /// Called by every row with the status it shows (on appearance and on each change). Entering
    /// needs input bumps the hop token once; a session already waiting when first seen never hops.
    /// A resting or waiting session that starts working bumps the excited token once; a session
    /// already working when first seen never gets excited.
    func noteStatus(key: SessionKey, status: FaceStatus) {
        if attention.observe(key: key, status: status) {
            attentionTokens[key] = attention.token(for: key)
        }
        if excited.observe(key: key, status: status) {
            // Counted here rather than copied from the tracker, so a scripted `--excite` never makes
            // the next real bump land on the same value.
            excitedTokens[key, default: 0] += 1
        }
    }

    // MARK: Excited

    /// The excited token of a row's face (0 until the session first started working while shown).
    func excitedToken(for key: SessionKey) -> Int {
        excitedTokens[key] ?? 0
    }

    /// `--excite`: every working row's face perks up as if its session had just started working.
    /// Debug only (scripted snapshots); the real trigger is `noteStatus`. Returns how many rows.
    @discardableResult
    func exciteWorkingRows() -> Int {
        let working = rows.filter { $0.status == .working }.map(\.key)
        for key in working {
            excitedTokens[key, default: 0] += 1
        }
        return working.count
    }

    // MARK: Capsule size

    /// Row slots of the live section: never below the empty stub, unless action faces fill the capsule.
    var capsuleRows: Int {
        Theme.liveSlots(rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Whether the divider is drawn (live section and action section both present).
    var hasDivider: Bool {
        Theme.hasDivider(rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Whether the divider below the new session button is drawn (the button and anything below it).
    var hasTopDivider: Bool {
        Theme.hasTopDivider(rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Height of the capsule body (between the fillets) for the current stores.
    var capsuleBodyHeight: CGFloat {
        Theme.capsuleBodyHeight(rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Final capsule height for the current stores; the window is sized with it.
    var capsuleHeight: CGFloat {
        Theme.capsuleHeight(rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Slot index of the hovered row, nil at rest or when the hovered row is gone.
    var hoveredRowIndex: Int? {
        if hoveredNewSession, showsNewSession { return Self.newSessionSlot }
        if let hoveredKey {
            return rows.firstIndex { $0.key == hoveredKey }
        }
        if let hoveredActionID, let index = actionRows.firstIndex(where: { $0.id == hoveredActionID }) {
            return rows.count + index
        }
        return nil
    }

    /// Whether a session row shows its name and status: the hovered row in `.row` mode, every row in `.all` mode.
    func isRowExpanded(_ key: SessionKey) -> Bool {
        guard throwingKey == nil else { return false }
        return switch expandMode {
        case .row: hoveredKey == key
        case .all: isExpanded
        }
    }

    /// Whether an action row shows its name and prompt (and opens its eyes).
    func isActionExpanded(_ id: String) -> Bool {
        guard throwingKey == nil else { return false }
        return switch expandMode {
        case .row: hoveredActionID == id
        case .all: isExpanded
        }
    }

    /// Whether the new session button shows its bulge text.
    var isNewSessionExpanded: Bool {
        guard throwingKey == nil else { return false }
        return switch expandMode {
        case .row: hoveredNewSession
        case .all: isExpanded
        }
    }

    /// How far beside the capsule (away from the screen edge) the expanded shape reaches (the
    /// clickable, hoverable bulge area).
    var bulgeReach: CGFloat {
        switch expandMode {
        case .row: Theme.bulgeWidth - Theme.bulgeOverlap
        case .all: Theme.bulgeWidth
        }
    }

    // MARK: Geometry

    /// Vertical centre of session row `index`, measured from the top of the capsule (fillet included).
    static func rowCenterY(index: Int) -> CGFloat {
        Theme.edgeFilletRadius + Theme.capsuleEndPadding + (CGFloat(index) + 0.5) * Theme.rowPitch
    }

    /// Vertical centre of the new session button, measured from the top of the capsule (fillet included).
    static var newSessionCenterY: CGFloat {
        Theme.edgeFilletRadius + Theme.capsuleEndPadding + Theme.newSessionPitch / 2
    }

    /// Vertical centre of a slot (the new session button at `newSessionSlot`, session rows below its
    /// section, then the action rows beyond the divider) for a capsule with `rows` live rows,
    /// `actions` action rows and, with `newSession`, the button.
    static func slotCenterY(slot: Int, rows: Int, actions: Int, newSession: Bool = false) -> CGFloat {
        if slot == newSessionSlot { return newSessionCenterY }
        let top = Theme.topSectionHeight(rows: rows, actions: actions, newSession: newSession)
        guard slot >= rows else { return rowCenterY(index: slot) + top }
        let live = Theme.liveSlots(rows: rows, actions: actions, newSession: newSession)
        let divider = Theme.hasDivider(rows: rows, actions: actions, newSession: newSession) ? Theme.dividerHeight : 0
        return rowCenterY(index: live + (slot - rows)) + divider + top
    }

    /// Vertical centre of a slot for the current stores.
    func slotCenterY(slot: Int) -> CGFloat {
        Self.slotCenterY(slot: slot, rows: rows.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// The open bulge of a slot in `.row` mode, at rest: centred on the slot, as tall as the slot plus
    /// `Theme.bulgePadding` on both sides (the new session button's is shorter than a row's), kept
    /// `Theme.bulgeEdgeMargin` inside the body by `GooLayout.bulgeSpan`, except at the first and the
    /// last slot (`isFirstSlot`, `isLastSlot`), where it moves flush with the body's top or bottom
    /// edge (a slot that is both spans the body). The goo, the droplets and the bulge texts all take
    /// it, so the texts sit centred in the blob that is drawn.
    static func bulgeSpan(slot: Int, rows: Int, actions: Int, newSession: Bool = false) -> GooLayout.BulgeSpan {
        let pitch = slot == newSessionSlot ? Theme.newSessionPitch : Theme.rowPitch
        let top = Theme.edgeFilletRadius
        let body = top ... top + Theme.capsuleBodyHeight(rows: rows, actions: actions, newSession: newSession)
        return GooLayout.bulgeSpan(
            slotCenterY: slotCenterY(slot: slot, rows: rows, actions: actions, newSession: newSession),
            height: GooLayout.bulgeHeight(pitch: pitch), body: body,
            flushTop: isFirstSlot(slot, rows: rows, actions: actions, newSession: newSession),
            flushBottom: isLastSlot(slot, rows: rows, actions: actions, newSession: newSession)
        )
    }

    /// Whether `slot` is the top one: the new session button, or without it slot 0 (the first session
    /// row, or the first action row when there are no rows).
    static func isFirstSlot(_ slot: Int, rows: Int, actions: Int, newSession: Bool = false) -> Bool {
        newSession ? slot == newSessionSlot : slot == 0 && rows + actions > 0
    }

    /// Whether `slot` is the bottom one: the last action row, or without actions the last session
    /// row, or the new session button when it is alone.
    static func isLastSlot(_ slot: Int, rows: Int, actions: Int, newSession: Bool = false) -> Bool {
        rows + actions > 0 ? slot == rows + actions - 1 : newSession && slot == newSessionSlot
    }

    /// The bulge span of a slot for the current stores.
    func bulgeSpan(slot: Int) -> GooLayout.BulgeSpan {
        Self.bulgeSpan(slot: slot, rows: visibleSessions.count, actions: actionRows.count, newSession: showsNewSession)
    }

    /// Where a slot's bulge texts go, relative to the slot's centre: the drawn blob's offset and
    /// height in `.row` mode; in `.all` mode the whole body widens, so they stay on the slot.
    func bulgeTextPlacement(slot: Int) -> (offset: CGFloat, height: CGFloat) {
        let span = bulgeSpan(slot: slot)
        switch expandMode {
        case .row: return (span.centerY - slotCenterY(slot: slot), span.height)
        case .all:
            let pitch = slot == Self.newSessionSlot ? Theme.newSessionPitch : Theme.rowPitch
            return (0, GooLayout.bulgeHeight(pitch: pitch))
        }
    }

    /// The slot at a vertical pointer position (from the top of the capsule). Positions in the end
    /// padding or the fillets snap to the nearest slot, positions in a divider band to the nearer
    /// side; outside the capsule (or with no slots) it is nil. The new session button is `newSessionSlot`.
    func rowIndex(atY y: CGFloat) -> Int? {
        let rowCount = rows.count
        let actionCount = actionRows.count
        guard y >= 0, y <= capsuleHeight else { return nil }
        let capsuleTop = Theme.edgeFilletRadius + Theme.capsuleEndPadding
        if showsNewSession {
            let band = Theme.hasTopDivider(rows: rowCount, actions: actionCount, newSession: true) ? Theme.dividerHeight / 2 : 0
            if rowCount + actionCount == 0 || y < capsuleTop + Theme.newSessionPitch + band { return Self.newSessionSlot }
        }
        guard rowCount + actionCount > 0 else { return nil }
        let top = capsuleTop + Theme.topSectionHeight(rows: rowCount, actions: actionCount, newSession: showsNewSession)
        let live = Theme.liveSlots(rows: rowCount, actions: actionCount, newSession: showsNewSession)
        let liveBottom = top + CGFloat(live) * Theme.rowPitch
        if rowCount > 0, y < liveBottom + (actionCount > 0 ? Theme.dividerHeight / 2 : 0) || actionCount == 0 {
            let index = Int(((y - top) / Theme.rowPitch).rounded(.down))
            return min(max(index, 0), rowCount - 1)
        }
        let actionsTop = liveBottom + (Theme.hasDivider(rows: rowCount, actions: actionCount, newSession: showsNewSession) ? Theme.dividerHeight : 0)
        let index = Int(((y - actionsTop) / Theme.rowPitch).rounded(.down))
        return rowCount + min(max(index, 0), actionCount - 1)
    }

    /// Whether a pointer `distanceFromEdge` points from the screen edge (into the screen, on either
    /// side) and `y` from the capsule's top is on the capsule column or, while expanded, on the open bulge.
    func hoverRegionContains(distanceFromEdge dx: CGFloat, y: CGFloat) -> HoverHit {
        guard dx >= 0, y >= 0, y <= capsuleHeight else { return .outside }
        if dx <= Theme.capsuleWidth { return .capsule }
        guard isExpanded, dx <= Theme.capsuleWidth + bulgeReach else { return .outside }
        switch expandMode {
        case .all:
            return .bulge
        case .row:
            guard let index = hoveredRowIndex else { return .outside }
            let span = bulgeSpan(slot: index)
            return y >= span.minY && y <= span.maxY ? .bulge : .outside
        }
    }

    /// What a pointer position hits.
    enum HoverHit: Equatable { case capsule, bulge, outside }

    /// The x of the capsule column's centre line in a view `width` wide that is anchored to the
    /// screen edge (the hosting view): where scripted pointers and clicks aim.
    func capsuleCenterX(inViewWidth width: CGFloat) -> CGFloat {
        side.x(fromEdge: Theme.capsuleWidth / 2, width: width)
    }

    // MARK: Magnification

    /// The magnification of the face in `slot` for the current pointer: the Gaussian falloff of
    /// the pointer's vertical distance to the slot centre sets the scale, the follow leans it toward
    /// the pointer, then `MagnifyColumn` fits it: inside the capsule width at the face's own box scale,
    /// and `Theme.rowBodyGap` clear of the neighbouring bodies (at the top of their grow), the divider
    /// line and the capsule's ends. Identity without a pointer or under another hover effect, and
    /// always for the new session button: it is a fixed body in the column, its neighbour fits
    /// around it. Builds the column from this slot and its two neighbours only.
    func magnify(slot: Int) -> MagnifyState {
        guard hoverEffect == .magnify, let pointer, slot != Self.newSessionSlot else { return .identity }
        let sessions = visibleSessions
        let rowCount = sessions.count
        let actionCount = actionStore?.visibleActions.count ?? 0
        let first = showsNewSession ? Self.newSessionSlot : 0
        guard slot >= first, slot < rowCount + actionCount else { return .identity }
        let slots = max(slot - 1, first)...min(slot + 1, rowCount + actionCount - 1)
        let column = Self.magnifyColumn(
            slots: slots, rows: rowCount, actions: actionCount, newSession: showsNewSession, faceSize: Theme.faceSize
        ) { self.faceReach(slot: $0, sessions: sessions) }
        return column.state(slot - slots.lowerBound, pointer: pointer)
    }

    /// The magnification column of `slots` (consecutive; `newSessionSlot` first when the button shows)
    /// in a capsule with `rows` live rows, `actions` action rows and, with `newSession`, the button:
    /// slot centres, the capsule body's inner ends and the divider lines. The button is a fixed face.
    static func magnifyColumn(
        slots: ClosedRange<Int>, rows: Int, actions: Int, newSession: Bool = false, faceSize: CGFloat = Theme.faceSize,
        reach: (Int) -> FaceReach
    ) -> MagnifyColumn {
        let top = Theme.edgeFilletRadius
        let bottom = top + Theme.capsuleBodyHeight(rows: rows, actions: actions, newSession: newSession)
        var dividers: [CGFloat] = []
        if Theme.hasTopDivider(rows: rows, actions: actions, newSession: newSession) {
            dividers.append(newSessionCenterY + Theme.newSessionPitch / 2 + Theme.dividerHeight / 2)
        }
        if Theme.hasDivider(rows: rows, actions: actions, newSession: newSession) {
            let lastLive = Theme.liveSlots(rows: rows, actions: actions, newSession: newSession) - 1
            let topSection = Theme.topSectionHeight(rows: rows, actions: actions, newSession: newSession)
            dividers.append(rowCenterY(index: lastLive) + topSection + Theme.rowPitch / 2 + Theme.dividerHeight / 2)
        }
        let faces = slots.map {
            MagnifyColumn.Face(
                centerY: slotCenterY(slot: $0, rows: rows, actions: actions, newSession: newSession), reach: reach($0),
                fixed: $0 == newSessionSlot
            )
        }
        return MagnifyColumn(faces: faces, top: top, bottom: bottom, dividers: dividers, faceSize: faceSize)
    }

    /// The reach of the face in `slot` (the button, or the session or action it shows, hovered or not).
    private func faceReach(slot: Int, sessions: [Session]) -> FaceReach {
        if slot == Self.newSessionSlot { return FaceReach.newSession() }
        let rowCount = sessions.count
        if slot < rowCount {
            let session = sessions[slot]
            let date = now()
            var status = SessionRow.faceStatus(
                state: session.state, isJustFinished: session.isJustFinished(at: date), ended: session.ended, stateSince: session.stateSince,
                idleTier: session.idleTier(acknowledgedAt: acknowledgements.time(for: session.key), now: date)
            )
            if RowDemo.enabled, slot < 2 { status = .working }
            return FaceReach.session(
                status: status, seed: SessionRow.seed(key: session.key, hostSessionId: session.hostSessionId), hovered: hoveredKey == session.key,
                style: FaceLook.style, shapeMode: FaceLook.blobShapeMode
            )
        }
        guard let item = actionStore?.visibleActions[slot - rowCount] else { return FaceReach.disc(faceSize: Theme.faceSize) }
        let row = ActionRow(item: item, launching: launchingActionIDs.contains(item.id))
        return FaceReach.action(row.face(hovered: hoveredActionID == item.id), style: FaceLook.style)
    }

    // MARK: Pointer events (from `PanelHostingView`)

    /// A pointer position in the hosting view's top-left coordinates, or nil when it left the window.
    /// On the capsule it picks the hovered row; on the open bulge it keeps it; anywhere else it ends
    /// the hover. The pointer itself is kept (in capsule coordinates) while on the capsule or the bulge.
    func pointerMoved(to point: CGPoint?, in size: CGSize) {
        guard !isDraggingPanel, throwingKey == nil else { return }
        guard let point else {
            setPointer(nil)
            hover(rowIndex: nil)
            return
        }
        let dx = side.distanceFromEdge(x: point.x, width: size.width)
        // The capsule's own coordinates: its inner edge is the screen edge's mirror.
        let capsulePoint = CGPoint(x: side.mirror(x: Theme.capsuleWidth - dx, in: Theme.capsuleWidth), y: point.y)
        switch hoverRegionContains(distanceFromEdge: dx, y: point.y) {
        case .capsule:
            setPointer(capsulePoint)
            hover(rowIndex: rowIndex(atY: point.y))
        case .bulge:
            setPointer(capsulePoint)
        case .outside:
            setPointer(nil)
            hover(rowIndex: nil)
        }
    }

    private func setPointer(_ point: CGPoint?) {
        if pointer != point { pointer = point }
    }

    /// Hover target by slot index (nil ends the hover). The window grows at once on the first
    /// hover and shrinks after the close spring settled; a new hover cancels a pending shrink.
    func hover(rowIndex: Int?) {
        let rows = rows
        let actions = actionRows
        let isNewSession = rowIndex == Self.newSessionSlot && showsNewSession
        guard let rowIndex, isNewSession || (rowIndex >= 0 && rowIndex < rows.count + actions.count) else {
            endHover()
            return
        }
        // A face on its way out never opens a bulge again.
        if rowIndex >= 0, rowIndex < rows.count, flownPoses[rows[rowIndex].key] != nil {
            endHover()
            return
        }
        pendingCollapse?.cancel()
        pendingCollapse = nil
        if !isExpanded {
            setWindowState?(.expanded(width: Theme.contentWidth))
            isExpanded = true
        }
        gooClosing = false
        let wasHovering = hoveredKey != nil || hoveredActionID != nil || hoveredNewSession
        bulgeRowIndex = rowIndex
        if isNewSession {
            if hoveredKey != nil { hoveredKey = nil }
            if hoveredActionID != nil { hoveredActionID = nil }
            if !hoveredNewSession {
                bulgeTravelled = wasHovering
                hoveredNewSession = true
            }
        } else if rowIndex < rows.count {
            let key = rows[rowIndex].key
            if hoveredNewSession { hoveredNewSession = false }
            if hoveredActionID != nil { hoveredActionID = nil }
            if hoveredKey != key {
                bulgeTravelled = wasHovering
                hoveredKey = key
            }
        } else {
            let id = actions[rowIndex - rows.count].id
            if hoveredNewSession { hoveredNewSession = false }
            if hoveredKey != nil { hoveredKey = nil }
            if hoveredActionID != id {
                bulgeTravelled = wasHovering
                hoveredActionID = id
            }
        }
    }

    private func endHover() {
        setPointer(nil)
        guard isExpanded || hoveredKey != nil || hoveredActionID != nil || hoveredNewSession else { return }
        hoveredKey = nil
        hoveredActionID = nil
        hoveredNewSession = false
        isExpanded = false
        gooClosing = true
        bulgeTravelled = false
        pendingCollapse?.cancel()
        pendingCollapse = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.closeSpringSettleTime))
            guard !Task.isCancelled else { return }
            self?.setWindowState?(.collapsed)
        }
    }

    // MARK: Slot count

    /// Animation for the current layout change: the open spring when the capsule grows or rows reorder;
    /// when it shrinks, the departure progress (`RowEntrance.departureAnimation`), because the stack's
    /// transaction animation is what drives a removal transition (measured: with the close spring here
    /// the slot began closing before the face had faded). Read in the view body before `layoutDidChange` runs.
    func layoutAnimation(rowCount: Int, actionCount: Int = 0, reduceMotion: Bool = false) -> Animation {
        let height = Theme.capsuleHeight(rows: rowCount, actions: actionCount, newSession: showsNewSession)
        guard let last = lastCapsuleHeight, height < last else { return Theme.openSpring }
        return RowEntrance.departureAnimation(reduceMotion: reduceMotion)
    }

    /// Delay before the hovered row's name appears: longer when the bulge had to travel from another row.
    var revealDelay: TimeInterval {
        bulgeTravelled ? Theme.revealTravelDelay : Theme.revealDelay
    }

    /// Spring for the goo shape: the close spring while the bulge melts, rows leave or a held face
    /// closed it, else the open spring.
    var gooAnimation: Animation {
        gooClosing || throwingKey != nil ? Theme.closeSpring : Theme.openSpring
    }

    /// Whether the goo bulge is open: expanded, and no face held.
    var isBulgeOpen: Bool {
        isExpanded && throwingKey == nil
    }

    /// Animation for the goo shape in a layout with this capsule height, read in the view body before
    /// `layoutDidChange` runs: when slots open or close, the capsule body follows them on the slot's own
    /// curve (`RowEntrance`), so the black shape and the rows move in lockstep; otherwise (hover, reorder)
    /// `gooAnimation`. Nil means at once (Reduce Motion opening a slot).
    func gooAnimation(capsuleHeight height: CGFloat, reduceMotion: Bool) -> Animation? {
        guard let last = lastCapsuleHeight, height != last else { return gooAnimation }
        return height > last
            ? RowEntrance.slotOpenAnimation(reduceMotion: reduceMotion)
            : RowEntrance.slotCloseAnimation(reduceMotion: reduceMotion)
    }

    /// The pop delays of the stack items that arrive in a layout with these ids (top to bottom),
    /// compared to the last layout; read in the view body before `layoutDidChange` runs. The first
    /// layout opens no slots, its faces only stagger in.
    /// The new session button and its divider never pop: they are no faces.
    func entranceDelays(stackIDs ids: [String], reduceMotion: Bool) -> [String: TimeInterval] {
        RowEntrance.faceDelays(previous: shownStackIDs, current: ids, reduceMotion: reduceMotion) {
            !["divider", Self.topDividerStackID, Self.newSessionStackID].contains($0)
        }
    }

    /// Stack ids (`CapsuleView`) of the new session button and of the divider below it.
    static let newSessionStackID = "new"
    static let topDividerStackID = "divider-top"

    /// Animation rule 4 for the session rows alone (the action count is the current one).
    func rowCountDidChange(_ count: Int) {
        layoutDidChange(rows: count, actions: actionRows.count)
    }

    /// Animation rule 4: grow the window first and animate inside it; on shrink animate first
    /// and resize the window once the spring settled. Called from the view when the slots changed.
    func layoutDidChange(rows rowCount: Int, actions actionCount: Int, stackIDs: [String]? = nil) {
        if let stackIDs { shownStackIDs = stackIDs }
        let previous = lastCapsuleHeight
        let height = Theme.capsuleHeight(rows: rowCount, actions: actionCount, newSession: showsNewSession)
        lastCapsuleHeight = height
        pendingShrink?.cancel()
        pendingShrink = nil
        if let previous, height < previous {
            gooClosing = hoveredKey == nil && hoveredActionID == nil && !hoveredNewSession
            pendingShrink = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Theme.closeSpringSettleTime))
                guard !Task.isCancelled else { return }
                self?.setWindowHeight?(height)
            }
        } else {
            if previous != nil { gooClosing = false }
            // Same height (a reorder) needs no resize.
            if previous != height { setWindowHeight?(height) }
        }
        if let hoveredKey, !rows.contains(where: { $0.key == hoveredKey }) {
            endHover()
        }
        if let hoveredActionID, !actionRows.contains(where: { $0.id == hoveredActionID }) {
            endHover()
        }
        let present = Set(rows.map(\.key))
        attention.keep(keys: present)
        excited.keep(keys: present)
        let acknowledged = acknowledgements.keeping(keys: present)
        if acknowledged != acknowledgements { acknowledgements = acknowledged }
        if attentionTokens.keys.contains(where: { !present.contains($0) }) {
            attentionTokens = attentionTokens.filter { present.contains($0.key) }
        }
        if excitedTokens.keys.contains(where: { !present.contains($0) }) {
            excitedTokens = excitedTokens.filter { present.contains($0.key) }
        }
        let actionIDs = Set(actionRows.map(\.id))
        if squintTokens.keys.contains(where: { !actionIDs.contains($0) }) {
            squintTokens = squintTokens.filter { actionIDs.contains($0.key) }
        }
    }

    // MARK: Press and drag (from `PanelDragController`)

    /// A press on the panel began (it may still become a drag). A new press always clicks again.
    func pressBegan() {
        swallowsTap = false
    }

    /// The press moved past `Theme.dragThreshold`: from now on it moves the window, and its release is no click.
    func dragBegan() {
        isDraggingPanel = true
        swallowsTap = true
    }

    /// The drag ended. Pointer reports flow again (the hosting view re-reports where the pointer is).
    func dragEnded() {
        isDraggingPanel = false
    }

    // MARK: Throw a face out (from `PanelDragController`)

    /// The session whose face a press at `point` (hosting view, top-left coordinates, `size` its
    /// size) could throw: on the capsule column, in a session slot, not already on its way out.
    /// Nil on an action face, the bulge, outside, or when there is no hidden store.
    func throwTarget(atViewPoint point: CGPoint, in size: CGSize) -> SessionKey? {
        guard hiddenSessions != nil else { return nil }
        let dx = side.distanceFromEdge(x: point.x, width: size.width)
        guard dx >= 0, dx <= Theme.capsuleWidth, let slot = rowIndex(atY: point.y) else { return nil }
        let rows = rows
        // The new session button (`newSessionSlot`) and the action faces cannot be thrown.
        guard slot >= 0, slot < rows.count else { return nil }
        let key = rows[slot].key
        return flownPoses[key] == nil ? key : nil
    }

    /// A press became a throw of `key`'s face: the release is no click, pointer reports freeze, the
    /// bulge closes (the window stays expanded, so the face has room to travel) and the face lifts.
    func throwBegan(key: SessionKey) {
        swallowsTap = true
        if hoveredKey != key, let slot = rows.firstIndex(where: { $0.key == key }) {
            hover(rowIndex: slot)
        }
        returnTask?.cancel()
        returningKey = nil
        throwPose = FaceThrowPose(motion: .immediate)
        throwingKey = key
    }

    /// The pointer moved while holding the face.
    func throwMoved(_ faceThrow: FaceThrow) {
        guard throwingKey == faceThrow.key else { return }
        let pose = faceThrow.heldPose(reduceMotion: reduceMotion())
        if throwPose != pose { throwPose = pose }
    }

    /// The face was let go. Out: it flies away for `throwFlyDuration`, then the session is hidden and
    /// its row departs. Back: it springs into its slot and nothing changes. Returns whether it is out.
    @discardableResult
    func throwEnded(_ faceThrow: FaceThrow) -> Bool {
        guard throwingKey == faceThrow.key else { return false }
        let key = faceThrow.key
        let release = faceThrow.release(reduceMotion: reduceMotion())
        throwPose = release.pose
        if release.removes {
            flownPoses[key] = release.pose
            throwingKey = nil
            if hoveredKey == key { endHover() }
            flyTasks[key]?.cancel()
            flyTasks[key] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.throwFlyDuration ?? Theme.throwFlyDuration))
                guard !Task.isCancelled else { return }
                self?.flyTasks[key] = nil
                self?.hideSession(key: key)
            }
        } else {
            throwingKey = nil
            returningKey = key
            returnTask?.cancel()
            returnTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Theme.closeSpringSettleTime))
                guard !Task.isCancelled, self?.returningKey == key else { return }
                self?.returningKey = nil
            }
        }
        return release.removes
    }

    /// Stops watching a session (its row departs). Matched by key and start, so a reused pid (or id) later shows.
    func hideSession(key: SessionKey) {
        guard let hiddenSessions else { return }
        if let session = store.sessions.first(where: { $0.key == key }) {
            hiddenSessions.hide(session)
        } else {
            flownPoses[key] = nil
        }
    }

    /// The throw pose of a session's face: the held pose while it is held, its fly-away once thrown
    /// out, else at rest. Reads `throwPose` only for the held face, so a move re-evaluates that face alone.
    func throwPose(for key: SessionKey) -> FaceThrowPose {
        if let flown = flownPoses[key] { return flown }
        return throwingKey == key ? throwPose : .rest
    }

    /// Whether a session's face draws above everything (held, springing back or flying away).
    func isLifted(_ key: SessionKey) -> Bool {
        throwingKey == key || returningKey == key || flownPoses[key] != nil
    }

    /// Number of hidden sessions (the menu bar item's count).
    var hiddenCount: Int { hiddenSessions?.count ?? 0 }

    /// Watches every session again: the hidden rows come back with the arrival animation.
    func showHiddenSessions() {
        flyTasks.values.forEach { $0.cancel() }
        flyTasks.removeAll()
        flownPoses.removeAll()
        hiddenSessions?.clear()
    }

    /// Drops hidden entries whose session left the registry (or whose pid now runs another session),
    /// and the fly-away poses of sessions that are gone. Only after the first scan: before it the
    /// list is empty and would prune everything. Live sessions the store filters out (another session
    /// source) are known by key alone; their entries stay, so a source switch forgets nothing.
    /// With sessions from other tools off, their entries stay too: the store knows nothing about them.
    func pruneHiddenSessions() {
        guard let hiddenSessions, store.hasScanned else { return }
        let sessions = store.sessions
        let present = Set(sessions.map(\.key))
        hiddenSessions.prune(
            keeping: sessions.map { ($0.key, $0.startedAt) }, otherKeys: store.presentKeys.subtracting(present),
            keepsExternal: !store.watchesExternal
        )
        if flownPoses.keys.contains(where: { !present.contains($0) }) {
            flownPoses = flownPoses.filter { present.contains($0.key) }
        }
    }

    /// Prunes on every change of the store's session list (the next scan after a hidden session left).
    private func observeSessionsForPruning() {
        pruneHiddenSessions()
        withObservationTracking {
            _ = store.hasScanned
            _ = store.sessions.map(\.key)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSessionsForPruning() }
        }
    }

    /// A click on a row opens its chat, and counts as the person having seen it: an idle period
    /// that began before now is no longer your turn.
    func tapped(_ row: SessionRow) {
        guard !swallowsTap else { return }
        acknowledgements.acknowledge(key: row.key, at: now())
        open(row)
    }

    /// The new session button was clicked: a session starts on the route of the session source, and
    /// the ring dips once (`newSessionClickToken`). A drag's release starts nothing.
    func tappedNewSession() {
        guard !swallowsTap, showsNewSession else { return }
        startNewSession(newSessionRoute)
        newSessionClickToken += 1
    }

    /// Runs an action: the launcher fires at once; the face squints for `Theme.actionSquintDuration`,
    /// then shows the working cloud for `Theme.actionLaunchFeedback` (one `Task.sleep` each, no timer).
    func tappedAction(_ row: ActionRow) {
        guard !swallowsTap else { return }
        guard let item = actionStore?.visibleActions.first(where: { $0.id == row.id }) else { return }
        hintTasks[row.id]?.cancel()
        sendHintActionIDs.remove(row.id)
        runAction(item) { [weak self] report in
            self?.launchReported(report, for: row.id)
        }
        squintTokens[row.id, default: 0] += 1
        launchTasks[row.id]?.cancel()
        launchTasks[row.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.actionSquintDuration))
            guard !Task.isCancelled, let self else { return }
            self.launchingActionIDs.insert(row.id)
            try? await Task.sleep(for: .seconds(Theme.actionLaunchFeedback))
            guard !Task.isCancelled else { return }
            self.launchingActionIDs.remove(row.id)
        }
    }

    /// A launch could only prefill the prompt: the bulge says so for `sendHintDuration`.
    func launchReported(_ report: ActionLaunch.Report, for id: String) {
        guard report == .needsManualSend else { return }
        sendHintActionIDs.insert(id)
        hintTasks[id]?.cancel()
        hintTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.sendHintDuration ?? Theme.actionSendHintDuration))
            guard !Task.isCancelled else { return }
            self?.sendHintActionIDs.remove(id)
        }
    }
}
