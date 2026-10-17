import SwiftUI

/// The black goo capsule: the new session button (when shown) and a divider at the top, then one face
/// per session stacked top to bottom in the body, then, below a divider, one face per action. The shape (`GooView`) and the content (faces, divider,
/// bulge texts) are separate layers positioned from the same slot geometry: the shape is blurred
/// and thresholded, text and eyes never are.
/// A thin line on the capsule's inner edge (left on the right side, right on the left side) marks
/// every waiting row (amber) and every your-turn row (the row's body colour, quieter) (`AttentionEdgeCueView`).
/// Arrival (`RowEntrance`): a new row's slot opens first (its height from 0 to the row pitch, ease-out),
/// the neighbours slide apart and the capsule body grows on the same curve; then the face pops in its
/// own layer tree, staggered when several rows arrive at once. Departure: the face shrinks and fades,
/// then the slot closes and the capsule with it. Reorders slide rows to their new slot on the open
/// spring. Action rows do the same when `actions.json` changes. An empty store shows the bare black
/// stub of one row height, or the action faces (or the new session button) alone when there are any.
/// The new session button never arrives or departs: it is part of the content from the first layout.
///
/// The stack has no spacing: every row is one `Theme.rowPitch` slot with its face centred, the
/// divider is `Theme.dividerHeight` tall, so a slot's height alone moves its neighbours.
///
/// The content is always laid out at `Theme.contentWidth` (capsule plus widest bulge) and aligned to
/// the screen edge (`PanelModel.side`: right-aligned, or left-aligned and mirrored on the left edge);
/// the window grows and shrinks around it (animation rule 4) and only ever reveals more or less of
/// it, nothing is re-laid out on resize.
struct CapsuleView: View {
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let rows = model.rows
        let actions = model.actionRows
        let top = (model.showsNewSession ? [PanelModel.newSessionStackID] : []) + (model.hasTopDivider ? [PanelModel.topDividerStackID] : [])
        let ids = top + rows.map { "s\($0.key)" } + (model.hasDivider ? ["divider"] : []) + actions.map { "a\($0.id)" }
        let capsuleHeight = model.capsuleHeight
        // A held face closes the bulge (the window stays expanded underneath).
        let isExpanded = model.isBulgeOpen
        // The blob's place, clamped inside the body (flush with its edge at the first and last
        // slot); the droplets trail the same centre.
        let bulge = model.bulgeSpan(slot: model.bulgeRowIndex)
        let bulgeCenterY = bulge.centerY
        let state = GooState(
            bodyHeight: model.capsuleBodyHeight,
            bodyExtraWidth: model.expandMode == .all && isExpanded ? Theme.bulgeWidth : 0,
            bulgeWidth: model.expandMode == .row && isExpanded ? Theme.bulgeWidth : 0,
            bulgeCenterY: bulgeCenterY,
            bulgeHeight: bulge.height,
            bulgeTopFlush: bulge.flushTop,
            bulgeBottomFlush: bulge.flushBottom
        )
        let gooAnimation = model.gooAnimation(capsuleHeight: capsuleHeight, reduceMotion: reduceMotion)
        let entrances = model.entranceDelays(stackIDs: ids, reduceMotion: reduceMotion)
        let allStagger = model.expandMode == .all ? Theme.allModeStagger : 0

        ZStack(alignment: model.side.edgeAlignment) {
            GooView(
                renderer: model.gooRenderer,
                expandMode: model.expandMode,
                state: state,
                dropletY: bulgeCenterY,
                capsuleHeight: capsuleHeight,
                animation: gooAnimation,
                reduceMotion: reduceMotion,
                isExpanded: isExpanded,
                side: model.side
            )
            .animation(Theme.dropletSpring, value: bulgeCenterY)

            VStack(spacing: 0) {
                if model.showsNewSession {
                    NewSessionRowView(
                        model: model,
                        expanded: model.isNewSessionExpanded,
                        hovered: model.hoveredNewSession,
                        revealDelay: model.revealDelay,
                        bulgeReach: model.bulgeReach,
                        reduceMotion: reduceMotion,
                        action: { model.tappedNewSession() }
                    )
                    .frame(height: Theme.newSessionPitch)
                    if model.hasTopDivider {
                        SectionDividerView(side: model.side)
                            .transition(dividerTransition)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                    SessionRowView(
                        model: model,
                        row: row,
                        slot: index,
                        expanded: model.isRowExpanded(row.key),
                        ticking: isExpanded && model.isRowExpanded(row.key),
                        revealDelay: model.revealDelay + Double(index) * allStagger,
                        bulgeReach: model.bulgeReach,
                        reduceMotion: reduceMotion,
                        attentionToken: model.attentionToken(for: row.key),
                        excitedToken: model.excitedToken(for: row.key),
                        hovered: model.hoveredKey == row.key,
                        lifted: model.isLifted(row.key),
                        enterDelay: entrances["s\(row.key)"] ?? 0,
                        onStatusChange: { model.noteStatus(key: row.key, status: $0) },
                        action: { model.tapped(row) }
                    )
                    .frame(height: Theme.rowPitch)
                    .transition(rowTransition)
                }
                if model.hasDivider {
                    SectionDividerView(side: model.side)
                        .transition(dividerTransition)
                }
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, row in
                    ActionRowView(
                        model: model,
                        row: row,
                        slot: rows.count + index,
                        expanded: model.isActionExpanded(row.id),
                        revealDelay: model.revealDelay + Double(rows.count + index) * allStagger,
                        bulgeReach: model.bulgeReach,
                        reduceMotion: reduceMotion,
                        hovered: model.hoveredActionID == row.id,
                        enterDelay: entrances["a\(row.id)"] ?? 0,
                        action: { model.tappedAction(row) }
                    )
                    .frame(height: Theme.rowPitch)
                    .transition(rowTransition)
                }
            }
            .frame(width: Theme.contentWidth)

            edgeCues(rows: rows, actionCount: actions.count)
        }
        .frame(width: Theme.contentWidth, height: capsuleHeight)
        .animation(model.layoutAnimation(rowCount: rows.count, actionCount: actions.count, reduceMotion: reduceMotion), value: ids)
        .onChange(of: ids, initial: true) { _, _ in
            model.layoutDidChange(rows: rows.count, actions: actions.count, stackIDs: ids)
        }
    }

    /// One line on the capsule's inner edge per waiting or your-turn row, at the row's slot (the row
    /// spring moves it on reorders), hidden while that row's bulge is open. Placed over the goo, outside it.
    private func edgeCues(rows: [SessionRow], actionCount: Int) -> some View {
        let cued = rows.enumerated().compactMap { slot, row in
            AttentionEdgeCue(status: row.status, bodyColor: FaceLook.bodyColor(for: row.status, seed: row.seed, projectKey: row.projectKey))
                .map { (slot: slot, row: row, cue: $0) }
        }
        return ZStack(alignment: .topLeading) {
            ForEach(cued, id: \.row.key) { slot, row, cue in
                let rect = AttentionEdgeLayout.rect(
                    slot: slot, rows: rows.count, actions: actionCount, newSession: model.showsNewSession, side: model.side
                )
                AttentionEdgeCueView(
                    cue: cue,
                    phase: FaceIdentity(seed: row.seed).pulsePhase,
                    visible: !model.isRowExpanded(row.key),
                    reduceMotion: reduceMotion
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(Theme.openSpring, value: rect.midY)
                .transition(.opacity)
            }
        }
        .frame(width: Theme.contentWidth, height: model.capsuleHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(Theme.closeSpring, value: cued.map(\.row.key))
    }

    /// Enter: the slot opens (the face pops in its layer tree). Exit: the face shrinks and fades, then
    /// the slot closes. Reduce Motion: the slot is there at once, the exit only fades.
    private var rowTransition: AnyTransition {
        RowEntrance.transition(height: Theme.rowPitch, reduceMotion: reduceMotion)
    }

    /// The divider band opens and closes like a slot (no face, no scale) and fades out on the way.
    private var dividerTransition: AnyTransition {
        RowEntrance.transition(height: SectionDividerView.stackHeight, scales: false, reduceMotion: reduceMotion)
    }
}
