import Foundation
import Testing
@testable import AgentOverview

@Suite("New session button: route and launch")
struct NewSessionLaunchTests {
    @Test("The route follows the session source: the Claude app for desktop sessions, Terminal otherwise")
    func routePerSource() {
        #expect(NewSessionLaunch.route(for: .desktop) == .claudeApp)
        #expect(NewSessionLaunch.route(for: .terminal) == .terminal)
        #expect(NewSessionLaunch.route(for: .everywhere) == .terminal)
        #expect(NewSessionLaunch.Route.claudeApp.title == "Claude app")
        #expect(NewSessionLaunch.Route.terminal.title == "Terminal")
    }

    @Test("The deep link is claude://code/new with no query")
    func deepLink() {
        let url = NewSessionLaunch.deepLink
        #expect(url.absoluteString == "claude://code/new")
        #expect(url.query == nil)
    }

    @Test("An empty prompt runs plain claude, with no argument, in the given folder")
    func emptyPromptScript() {
        let script = ActionLaunch.commandScript(cwd: "/Users/demo", prompt: "")
        #expect(script == "#!/bin/zsh\ncd '/Users/demo' && exec claude\n")
        #expect(ActionLaunch.commandScript(cwd: "/Users/demo", prompt: "  \n") == script, "whitespace is no prompt either")
        #expect(NewSessionLaunch.commandScript(home: "/Users/demo") == script)
        #expect(ActionLaunch.commandScript(cwd: "/Users/demo", prompt: "hi").hasSuffix("exec claude 'hi'\n"), "a prompt is still the first message")
    }

    @Test("Run: the Claude app route opens the link; the terminal route writes the command file and opens it quietly")
    @MainActor
    func runWithInjectedEffects() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var opened: [URL] = []
        var quiet: [URL] = []
        let effects = ActionLaunch.Effects(
            open: { opened.append($0) },
            openAndSend: { _, _, _ in Issue.record("the new session never sends a prompt") },
            commandFolder: folder,
            openInBackground: { quiet.append($0) }
        )
        NewSessionLaunch.run(.claudeApp, effects: effects, home: "/Users/demo")
        #expect(opened == [NewSessionLaunch.deepLink] && quiet.isEmpty)

        NewSessionLaunch.run(.terminal, effects: effects, home: "/Users/demo")
        #expect(opened.count == 1 && quiet.count == 1)
        let file = try #require(quiet.first)
        #expect(file.lastPathComponent == Theme.newSessionCommandFile)
        #expect(file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == "#!/bin/zsh\ncd '/Users/demo' && exec claude\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }
}

@Suite("New session button: panel model")
@MainActor
struct NewSessionModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "NewSessionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// `sessions` live sessions and `actions` action faces, with or without the button.
    private func makeModel(
        sessions: Int = 2, actions: Int = 0, newSession: Bool = true, source: SessionSource = .desktop, hidden: HiddenSessions? = nil
    ) throws -> (SessionStore, ActionStore?, PanelModel) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var records: [SessionRecord] = []
        for index in 0..<sessions {
            var record = try TestSupport.fixtureRecord(index == 0 ? "idle-desktop" : "busy-desktop")
            record.pid = TestSupport.livePids[index]
            records.append(record)
        }
        store.reconcile(RegistryScanResult(records: records, presentPids: Set(records.map(\.pid))))
        var actionStore: ActionStore?
        if actions > 0 {
            let folder = try TestSupport.makeTempFolder()
            let file = folder.appending(path: "actions.json")
            let items = (0..<actions).map { ActionItem(id: "a\($0)", name: "A\($0)", cwd: "/tmp", prompt: "p") }
            try ActionItem.encode(items).write(to: file)
            actionStore = ActionStore(fileURL: file)
            actionStore?.start()
        }
        let model = PanelModel(
            store: store, actionStore: actionStore, hiddenSessions: hidden, newSessionButton: newSession, sessionSource: source
        )
        return (store, actionStore, model)
    }

    @Test("Capsule height grows by the button's pitch plus its divider; the button alone needs no stub")
    func capsuleHeight() throws {
        let section = Theme.newSessionPitch + Theme.dividerHeight
        #expect(Theme.newSessionPitch < Theme.rowPitch && Theme.newSessionSize < Theme.faceSize)
        #expect(Theme.capsuleHeight(rows: 2, actions: 0, newSession: true) == Theme.capsuleHeight(rows: 2, actions: 0) + section)
        #expect(Theme.capsuleHeight(rows: 2, actions: 1, newSession: true) == Theme.capsuleHeight(rows: 2, actions: 1) + section)
        #expect(Theme.capsuleHeight(rows: 0, actions: 2, newSession: true) == Theme.capsuleHeight(rows: 0, actions: 2) + section)
        let alone = Theme.capsuleEndPadding * 2 + Theme.edgeFilletRadius * 2 + Theme.newSessionPitch
        #expect(Theme.capsuleHeight(rows: 0, actions: 0, newSession: true) == alone, "no stub, no divider")
        #expect(Theme.liveSlots(rows: 0, actions: 0, newSession: true) == 0)
        #expect(!Theme.hasTopDivider(rows: 0, actions: 0, newSession: true) && Theme.hasTopDivider(rows: 1, actions: 0, newSession: true))
        #expect(!Theme.hasTopDivider(rows: 3, actions: 3, newSession: false))

        let (store, actionStore, model) = try makeModel(actions: 2)
        defer { store.stop(); actionStore?.stop() }
        #expect(model.showsNewSession && model.hasTopDivider && model.hasDivider)
        #expect(model.capsuleHeight == Theme.capsuleHeight(rows: 2, actions: 2) + section)
        #expect(model.capsuleBodyHeight == Theme.capsuleBodyHeight(rows: 2, actions: 2) + section)
        #expect(model.slotCount == 4, "the button is no row or action slot")

        let (offStore, _, off) = try makeModel(newSession: false)
        defer { offStore.stop() }
        #expect(!off.showsNewSession && !off.hasTopDivider && off.capsuleHeight == Theme.capsuleHeight(rows: 2, actions: 0))
    }

    @Test("Slot centres and the pointer maths: the rows sit below the button's section, the button is its own slot")
    func geometry() throws {
        let (store, actionStore, model) = try makeModel(actions: 1)
        defer { store.stop(); actionStore?.stop() }
        let section = Theme.newSessionPitch + Theme.dividerHeight
        let top = Theme.edgeFilletRadius + Theme.capsuleEndPadding
        #expect(model.slotCenterY(slot: PanelModel.newSessionSlot) == top + Theme.newSessionPitch / 2)
        #expect(model.slotCenterY(slot: 0) == PanelModel.rowCenterY(index: 0) + section)
        #expect(model.slotCenterY(slot: 1) == PanelModel.rowCenterY(index: 1) + section)
        #expect(model.slotCenterY(slot: 2) == PanelModel.rowCenterY(index: 2) + section + Theme.dividerHeight, "the action below both dividers")

        let controlBottom = top + Theme.newSessionPitch
        #expect(model.rowIndex(atY: 0) == PanelModel.newSessionSlot, "the top fillet snaps to the button")
        #expect(model.rowIndex(atY: controlBottom - 1) == PanelModel.newSessionSlot)
        #expect(model.rowIndex(atY: controlBottom + Theme.dividerHeight / 2 - 1) == PanelModel.newSessionSlot, "upper half of its divider band")
        #expect(model.rowIndex(atY: controlBottom + Theme.dividerHeight / 2 + 1) == 0, "lower half to the first row")
        #expect(model.rowIndex(atY: controlBottom + Theme.dividerHeight + Theme.rowPitch + 1) == 1)
        #expect(model.rowIndex(atY: model.capsuleHeight) == 2, "the bottom fillet snaps to the last action")
        #expect(model.containsSlot(PanelModel.newSessionSlot) && model.containsSlot(2) && !model.containsSlot(3))

        // The amber edge cue follows the rows down.
        let cue = AttentionEdgeLayout.rect(slot: 1, rows: 2, actions: 1, newSession: true)
        #expect(abs(cue.midY - model.slotCenterY(slot: 1)) < 0.000_001)

        let (aloneStore, _, alone) = try makeModel(sessions: 0)
        defer { aloneStore.stop() }
        #expect(alone.rowIndex(atY: alone.capsuleHeight / 2) == PanelModel.newSessionSlot && !alone.hasTopDivider)

        let (offStore, _, off) = try makeModel(newSession: false)
        defer { offStore.stop() }
        #expect(!off.containsSlot(PanelModel.newSessionSlot))
        #expect(off.rowIndex(atY: 0) == 0 && off.slotCenterY(slot: 0) == PanelModel.rowCenterY(index: 0), "nothing moves without the button")
    }

    @Test("Hover: the bulge opens on the button and ends like any other; the route names where it opens")
    func hover() throws {
        let (store, _, model) = try makeModel(source: .terminal)
        defer { store.stop() }
        var states: [PanelWindowState] = []
        model.setWindowState = { states.append($0) }
        model.hover(rowIndex: PanelModel.newSessionSlot)
        #expect(model.hoveredNewSession && model.isNewSessionExpanded && model.isExpanded)
        #expect(model.hoveredRowIndex == PanelModel.newSessionSlot && model.bulgeRowIndex == PanelModel.newSessionSlot)
        #expect(states == [.expanded(width: Theme.contentWidth)])
        #expect(model.newSessionRoute == .terminal)
        model.hover(rowIndex: 0)
        #expect(!model.hoveredNewSession && model.hoveredRowIndex == 0 && model.bulgeTravelled)
        model.hover(rowIndex: nil)
        #expect(!model.hoveredNewSession && !model.isExpanded)

        let (offStore, _, off) = try makeModel(newSession: false)
        defer { offStore.stop() }
        off.hover(rowIndex: PanelModel.newSessionSlot)
        #expect(!off.hoveredNewSession && !off.isExpanded, "no button, no hover")
    }

    @Test("Click: starts a session on the route and dips the ring; a drag's release starts nothing")
    func click() throws {
        let (store, _, model) = try makeModel()
        defer { store.stop() }
        var routes: [NewSessionLaunch.Route] = []
        model.startNewSession = { routes.append($0) }
        model.tappedNewSession()
        #expect(routes == [.claudeApp] && model.newSessionClickToken == 1)
        model.pressBegan()
        model.dragBegan()
        model.tappedNewSession()
        #expect(routes.count == 1 && model.newSessionClickToken == 1, "the release of a panel drag")
        model.dragEnded()
        model.pressBegan()
        model.tappedNewSession()
        #expect(routes.count == 2 && model.newSessionClickToken == 2)
    }

    @Test("The button cannot be thrown, and it stays when every session is hidden")
    func excludedFromThrowAndHiddenSessions() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, _, model) = try makeModel(hidden: hidden)
        defer { store.stop() }
        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        let x = size.width - Theme.capsuleWidth / 2
        #expect(model.throwTarget(atViewPoint: CGPoint(x: x, y: model.slotCenterY(slot: PanelModel.newSessionSlot)), in: size) == nil)
        #expect(model.throwTarget(atViewPoint: CGPoint(x: x, y: model.slotCenterY(slot: 0)), in: size) == model.rows[0].key)

        for session in store.sessions { hidden.hide(session) }
        #expect(model.rows.isEmpty && model.showsNewSession)
        #expect(!model.hasTopDivider)
        #expect(model.capsuleHeight == Theme.capsuleHeight(rows: 0, actions: 0, newSession: true), "the button alone, no empty stub")
        #expect(model.rowIndex(atY: model.slotCenterY(slot: PanelModel.newSessionSlot)) == PanelModel.newSessionSlot)
    }

    @Test("Magnification: the button never magnifies, the column keeps the body gap to it and to both dividers")
    func magnify() throws {
        let (store, actionStore, model) = try makeModel(actions: 1)
        defer { store.stop(); actionStore?.stop() }
        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        let x = size.width - Theme.capsuleWidth / 2
        model.pointerMoved(to: CGPoint(x: x, y: model.slotCenterY(slot: PanelModel.newSessionSlot)), in: size)
        #expect(model.hoveredNewSession)
        #expect(model.magnify(slot: PanelModel.newSessionSlot) == .identity, "under the pointer, and still not magnified")
        #expect(model.magnify(slot: 0).scale > 1 && model.magnify(slot: 0).dy < 0, "the first row still leans up toward it")
        model.pointerMoved(to: CGPoint(x: x, y: model.slotCenterY(slot: 0)), in: size)
        #expect(model.magnify(slot: PanelModel.newSessionSlot) == .identity, "nor from a neighbour's hover")

        // A sweep of the pointer down the column: no body comes closer than the gap to another, a divider or an end.
        let rows = 2, actions = 1
        let slots = PanelModel.newSessionSlot...(rows + actions - 1)
        let column = PanelModel.magnifyColumn(slots: slots, rows: rows, actions: actions, newSession: true) { slot in
            switch slot {
            case PanelModel.newSessionSlot: FaceReach.newSession()
            case ..<rows: FaceReach.session(status: .working, seed: "s\(slot)", hovered: false)
            default: FaceReach.action(ActionFace(phase: .resting))
            }
        }
        #expect(column.dividers.count == 2)
        #expect(column.faces[0].centerY == PanelModel.newSessionCenterY)
        let height = Theme.capsuleHeight(rows: rows, actions: actions, newSession: true)
        #expect(column.faces[0].fixed && !column.faces[1].fixed)
        var minGap = CGFloat.infinity
        var y: CGFloat = 0
        while y <= height {
            let states = column.states(pointer: CGPoint(x: Theme.capsuleWidth / 2, y: y))
            #expect(states[0] == .identity)
            for (index, state) in states.enumerated() {
                let face = column.faces[index]
                let top = face.centerY + state.dy - state.scale * face.reach.up
                let bottom = face.centerY + state.dy + state.scale * face.reach.down
                if index == 0 { minGap = min(minGap, top - column.top) }
                if index == states.count - 1 { minGap = min(minGap, column.bottom - bottom) }
                for divider in column.dividers {
                    minGap = min(minGap, face.centerY < divider ? divider - bottom : top - divider)
                }
                if index < states.count - 1 {
                    let next = column.faces[index + 1]
                    let nextTop = next.centerY + states[index + 1].dy - states[index + 1].scale * next.reach.up
                    minGap = min(minGap, nextTop - bottom)
                }
            }
            y += 0.5
        }
        #expect(minGap >= Theme.rowBodyGap - 0.000_1, "\(minGap)")
        #expect(FaceReach.newSession().up == Theme.newSessionSize / 2 && FaceReach.newSession().boxScale < 1)
    }

    @Test("A fixed face keeps its own reach of the shared room; a magnified neighbour stops the gap short of it")
    func fixedFaceShare() {
        // No divider between them: the share rule alone keeps the gap.
        let ring = FaceReach.newSession()
        let face = FaceReach.disc(faceSize: Theme.faceSize)
        let pitch = Theme.newSessionSize / 2 + Theme.faceSize / 2 + Theme.rowBodyGap + 6
        let column = MagnifyColumn(
            faces: [MagnifyColumn.Face(centerY: 40, reach: ring, fixed: true), MagnifyColumn.Face(centerY: 40 + pitch, reach: face)],
            top: 0, bottom: 400
        )
        var squeezed = false
        var y: CGFloat = 0
        while y <= 160 {
            let pointer = CGPoint(x: Theme.capsuleWidth / 2, y: y)
            let share = column.share(upper: 0, pointer: pointer)
            #expect(share.upper == ring.down, "the fixed face takes exactly its reach")
            let states = column.states(pointer: pointer)
            #expect(states[0] == .identity)
            let neighbourTop = column.faces[1].centerY + states[1].dy - states[1].scale * face.up
            #expect(neighbourTop - (column.faces[0].centerY + ring.down) >= Theme.rowBodyGap - 0.000_1)
            if column.raw(1, pointer: pointer).scale > states[1].scale + 0.001 { squeezed = true }
            y += 0.5
        }
        #expect(squeezed, "the neighbour was held back at least once, so the rule was tested")
    }

    @Test("Glyph: white and turned while hovered, no turn under Reduce Motion")
    func glyphState() {
        let rest = NewSessionGlyphState()
        let hovered = NewSessionGlyphState(hovered: true)
        let calm = NewSessionGlyphState(hovered: true, reduceMotion: true)
        #expect(NewSessionGlyph.plusAngle(rest) == 0)
        #expect(abs(NewSessionGlyph.plusAngle(hovered)) == Theme.newSessionPlusTurn)
        #expect(NewSessionGlyph.plusAngle(calm) == 0)
        #expect(NewSessionGlyph.color(hovered) == Theme.newSessionHoverColor && NewSessionGlyph.color(rest) == Theme.newSessionRestColor)
        let box = CGRect(x: 0, y: 0, width: Theme.faceSize, height: Theme.faceSize)
        let ring = NewSessionGlyph.ringPath(in: box).boundingBoxOfPath
        #expect(abs(ring.width - Theme.newSessionSize) < 0.01 && abs(ring.midX - box.midX) < 0.01)
        #expect(NewSessionGlyph.plusPath(in: box).boundingBoxOfPath.width < ring.width)
    }
}

@Suite("New session button: setting and launch arguments")
@MainActor
struct NewSessionSettingTests {
    @Test("On by default, stored when changed, read back; --set takes on and off")
    func roundTrip() {
        let name = "NewSessionSetting-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.newSessionButton == Theme.newSessionButton && Theme.newSessionButton)
        settings.newSessionButton = false
        #expect(defaults.object(forKey: AppSettings.Key.newSessionButton) as? Bool == false)
        #expect(AppSettings(defaults: defaults).newSessionButton == false)
        #expect(settings.setValue("on", forKey: "newSessionButton") && settings.newSessionButton)
        #expect(settings.setValue("off", forKey: "newSessionButton") && !settings.newSessionButton)
        #expect(settings.setValue("true", forKey: "newSessionButton") && settings.newSessionButton)
        #expect(!settings.setValue("maybe", forKey: "newSessionButton") && settings.newSessionButton)
        #expect(AppSettings(defaults: defaults).newSessionButton)
        let forced = AppSettings(defaults: defaults, overrides: AppSettings.Overrides(newSessionButton: false))
        #expect(!forced.newSessionButton)
        #expect(settings.isAppearanceDefault, "not an appearance value: Restore defaults leaves it alone")
    }

    @Test("--hover new targets the button")
    func hoverArgument() {
        #expect(LaunchArguments.HoverTarget("new") == .newSession)
        #expect(LaunchArguments.HoverTarget.newSession.slotIndex(rowCount: 3) == PanelModel.newSessionSlot)
        #expect(LaunchArguments(["app", "--hover", "new"]).hover == .newSession)
        #expect(LaunchArguments(["app", "--set", "newSessionButton=off"]).scriptedSettings.map(\.value) == ["off"])
    }
}
