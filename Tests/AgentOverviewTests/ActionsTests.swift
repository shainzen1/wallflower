import Foundation
import Testing
@testable import AgentOverview

extension ActionItem {
    /// A neutral example action for the tests (the app itself ships with none).
    static let standup = ActionItem(id: "standup", name: "Standup", cwd: "~", prompt: "/standup")
}

@Suite("Action items")
struct ActionItemTests {
    @Test("Decoding: full and minimal items, unknown shapes and bad colours ignored, round trip")
    func decoding() throws {
        let json = """
        [
          {"id": "standup", "name": "Standup", "cwd": "~", "prompt": "/standup"},
          {"id": "x", "name": "X", "cwd": "/tmp", "prompt": "hi", "seed": "s", "symbol": "star", "shape": "gem", "color": "#8C7CFF"},
          {"id": "y", "name": "Y", "cwd": "/tmp", "prompt": "yo", "shape": "cloud", "color": "nope"}
        ]
        """
        let items = try ActionItem.decode(Data(json.utf8))
        #expect(items.count == 3)
        #expect(items[0] == .standup)
        #expect(items[0].faceSeed == "action-standup" && items[0].blobShape == nil && items[0].bodyColor == nil)
        #expect(items[0].resolvedCwd == NSString(string: "~").expandingTildeInPath && !items[0].resolvedCwd.hasPrefix("~"))
        #expect(items[1].faceSeed == "s" && items[1].symbol == "star" && items[1].blobShape == nil, "an unknown shape falls back")
        #expect(items[1].bodyColor == EyeColor(hex: "#8C7CFF", name: "action x"))
        #expect(items[2].blobShape == .cloud && items[2].bodyColor == nil, "a bad colour falls back")
        let again = try ActionItem.decode(try ActionItem.encode(items))
        #expect(again == items)
        #expect(throws: (any Error).self) { try ActionItem.decode(Data("[{\"id\": \"no-name\"}]".utf8)) }
        #expect(throws: (any Error).self) { try ActionItem.decode(Data("not json".utf8)) }
    }

    @Test("Rows: the Theme look unless the item overrides it; the face phase follows hover and launch")
    func rows() {
        let plain = ActionRow(item: .standup)
        #expect(plain.shape == Theme.actionShape && plain.color == Theme.actionColor && plain.name == "Standup" && plain.prompt == "/standup")
        #expect(plain.face(hovered: false) == ActionFace(phase: .resting))
        #expect(plain.face(hovered: true).phase == .hovered)
        let custom = ActionRow(item: ActionItem(id: "c", name: "C", cwd: "/", prompt: "p", shape: "pebble", color: "#FF0000"), launching: true, squintToken: 2)
        #expect(custom.shape == .pebble && custom.color.red == 1 && custom.squintToken == 2)
        #expect(custom.face(hovered: true).phase == .launching, "launching wins over hover")
        #expect(Theme.actionShape == .star && BlobShape.allCases.contains(.star))
    }

    @Test("Launch: the new-session deep link carries folder and prompt; the terminal fallback is a quoted zsh script")
    func launch() throws {
        let item = ActionItem.standup
        let url = try #require(ActionLaunch.deepLink(for: item))
        #expect(url.scheme == "claude" && url.host == "code" && url.path == "/new")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "folder" }?.value == item.resolvedCwd)
        #expect(query.first { $0.name == "q" }?.value == "/standup")
        #expect(query.map(\.name) == ["folder", "q"], "the app drops every other parameter, so there is no submit flag to add")
        let script = ActionLaunch.commandScript(for: ActionItem(id: "q", name: "Q", cwd: "/tmp/it's", prompt: "say \"hi\""))
        #expect(script.hasPrefix("#!/bin/zsh\n"))
        #expect(script.contains("cd '/tmp/it'\\''s' && exec claude 'say \"hi\"'"))
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try ActionLaunch.writeCommandFile(for: item, in: folder)
        #expect(file.pathExtension == "command")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
        #expect(try String(contentsOf: file, encoding: .utf8) == ActionLaunch.commandScript(for: item))
    }

    @Test("Send guard: Return only while Claude is frontmost and within the send window")
    func sendGuard() {
        let claude = SessionOpener.claudeBundleIdentifier
        #expect(claude == "com.anthropic.claudefordesktop")
        #expect(ActionLaunch.shouldSend(frontmostBundleID: claude, elapsed: 1.2))
        #expect(ActionLaunch.shouldSend(frontmostBundleID: claude, elapsed: Theme.actionSendWindow - 0.01))
        #expect(!ActionLaunch.shouldSend(frontmostBundleID: claude, elapsed: Theme.actionSendWindow), "too late")
        #expect(!ActionLaunch.shouldSend(frontmostBundleID: claude, elapsed: 30))
        #expect(!ActionLaunch.shouldSend(frontmostBundleID: claude, elapsed: -0.1))
        #expect(!ActionLaunch.shouldSend(frontmostBundleID: "com.apple.Safari", elapsed: 1), "another app is frontmost")
        #expect(!ActionLaunch.shouldSend(frontmostBundleID: nil, elapsed: 1), "nothing frontmost (locked screen)")
        #expect(ActionLaunch.shouldSend(frontmostBundleID: "x", elapsed: 1, claudeBundleID: "x", window: 2))
        #expect(Theme.actionActivationTimeout <= 2)
        // Measured worst case: prefill 2.4 s, slash prompt (retype, settle, two Returns) about 1.5 s, sent check.
        let worst = 2.4 + Theme.actionSendDelay + 2 * Theme.actionReactTimeout + Theme.actionSentConfirm
        #expect(worst < Theme.actionSendWindow, "the slowest measured prefill still sends inside the window")
        #expect(Theme.actionMaxKeyActions >= 3, "retype plus two Returns for a slash prompt")
    }

    @Test("Composer states: blank, exact, defused, the picked command; anything else is someone's text")
    func composerStates() {
        #expect(ActionLaunch.composerState(text: "/standup", prompt: "/standup") == .prompt)
        #expect(ActionLaunch.composerState(text: "\u{FF0F}standup", prompt: "/standup") == .defusedPrompt, "the page defuses a leading slash")
        #expect(ActionLaunch.composerState(text: "\u{FF01}ls", prompt: "!ls") == .defusedPrompt)
        #expect(ActionLaunch.composerState(text: "ask \u{FF20}file", prompt: "ask @file") == .defusedPrompt)
        #expect(ActionLaunch.composerState(text: "say hello in one word\n", prompt: "say hello in one word") == .prompt, "trailing newline")
        #expect(ActionLaunch.composerState(text: "standup ", prompt: "/standup") == .pickedCommand, "the first Return turned the slash into a chip")
        #expect(ActionLaunch.composerState(text: "say hello", prompt: "say hello in one word") == .other)
        #expect(ActionLaunch.composerState(text: "", prompt: "/standup") == .blank)
        #expect(ActionLaunch.composerState(text: "\n", prompt: "/standup") == .blank)
        #expect(ActionLaunch.composerState(text: "a", prompt: "/standup") == .other, "someone's draft")
        #expect(ActionLaunch.composerState(text: "standup", prompt: "standup x") == .other)
        #expect(ActionLaunch.composerState(text: "x", prompt: "  ") == .other, "an empty prompt never matches")
    }

    @Test("Send steps: retype the defused prompt, Return on the prompt or the picked command, sent only once empty after our Return")
    func sendSteps() {
        #expect(ActionLaunch.sendStep(for: nil, returnInFocus: false) == .wait, "no composer in focus")
        #expect(ActionLaunch.sendStep(for: .other, returnInFocus: false) == .wait)
        #expect(ActionLaunch.sendStep(for: .other, returnInFocus: true) == .wait, "never press Return on someone's text")
        #expect(ActionLaunch.sendStep(for: .defusedPrompt, returnInFocus: false) == .retype)
        #expect(ActionLaunch.sendStep(for: .defusedPrompt, returnInFocus: true) == .retype, "the page reloaded and prefilled again")
        #expect(ActionLaunch.sendStep(for: .prompt, returnInFocus: false) == .pressReturn)
        #expect(ActionLaunch.sendStep(for: .pickedCommand, returnInFocus: false) == .wait, "not ours unless we pressed Return")
        #expect(ActionLaunch.sendStep(for: .pickedCommand, returnInFocus: true) == .pressReturn)
        #expect(ActionLaunch.sendStep(for: .blank, returnInFocus: false) == .wait, "not prefilled yet, or empty after the focus left (a dialog): never counted as sent")
        // The page behind "Trust this workspace?": the composer never holds the prompt, so nothing is ever pressed.
        let blocked: [ActionLaunch.ComposerState?] = [nil, .blank, nil, .other, nil]
        #expect(blocked.allSatisfy { ActionLaunch.sendStep(for: $0, returnInFocus: false) == .wait })
        #expect(ActionLaunch.sendStep(for: .blank, returnInFocus: true) == .confirmSent)
    }

    @Test("Launcher switch: prefill only, prefill and send, terminal; each reports what the person still has to do")
    @MainActor
    func launcherSwitch() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var opened: [URL] = []
        var sent: [URL] = []
        var reports: [ActionLaunch.Report] = []
        let effects = ActionLaunch.Effects(
            open: { opened.append($0) },
            openAndSend: { url, prompt, report in
                sent.append(url)
                #expect(prompt == "/standup")
                report(.sent)
            },
            commandFolder: folder,
            openInBackground: { opened.append($0) }
        )
        let item = ActionItem.standup
        let link = try #require(ActionLaunch.deepLink(for: item))
        #expect(Theme.actionLauncher == .terminalCommand && Theme.terminalOpensInBackground)

        ActionLaunch.run(item, using: .deepLinkNew, effects: effects) { reports.append($0) }
        #expect(opened == [link] && sent.isEmpty && reports == [.needsManualSend])

        ActionLaunch.run(item, using: .deepLinkAndSend, effects: effects) { reports.append($0) }
        #expect(opened == [link] && sent == [link] && reports == [.needsManualSend, .sent])

        ActionLaunch.run(item, using: .terminalCommand, effects: effects) { reports.append($0) }
        #expect(opened.count == 2 && opened[1].pathExtension == "command" && opened[1].deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(reports == [.needsManualSend, .sent, .sent])
    }

    @Test("Face programs: resting sleepy, hovered normal, launching the working cloud, all in the action colour; the squint is a one-shot")
    func programs() {
        let identity = FaceIdentity(seed: "action")
        let resting = BlobProgramBuilder.program(for: .action(ActionFace(phase: .resting)), identity: identity)
        #expect(resting.pose == BlobProgramBuilder.restingActionPose(identity) && resting.body.shape == .star && resting.color == Theme.actionColor)
        #expect(resting.pose.left.height < BlobProgramBuilder.resolved(.normal, identity).left.height / 2, "lids nearly closed at rest")
        #expect(resting.tracks.map(\.key) == ["loop.sleepy"] && resting.bodyLoop == nil)
        let hovered = BlobProgramBuilder.program(for: .action(ActionFace(phase: .hovered)), identity: identity)
        #expect(hovered.pose == BlobProgramBuilder.resolved(.normal, identity) && hovered.body.shape == .star && hovered.tracks.map(\.key) == ["loop.idle"])
        let launching = BlobProgramBuilder.program(for: .action(ActionFace(phase: .launching)), identity: identity)
        #expect(launching.body.shape == Theme.blobWorkingShape && launching.color == Theme.actionColor && launching.bodyLoop == Theme.blobWorkingBreath)
        let custom = BlobProgramBuilder.program(for: .action(ActionFace(phase: .resting, shape: .pebble, color: Theme.workingColor)), identity: identity)
        #expect(custom.body.shape == .pebble && custom.color == Theme.workingColor)
        let squint = BlobProgramBuilder.squintTrack(from: resting.pose, identity: identity)
        #expect(squint.key == "oneshot.squint" && !squint.repeats && abs(squint.duration - Theme.actionSquintDuration) < 0.001)
        #expect(squint.samples.first?.pose == resting.pose && squint.samples.last?.pose == resting.pose)
        let glee = BlobProgramBuilder.resolved(.glee, identity)
        #expect(squint.samples.contains { $0.pose.left.height == glee.left.height }, "reaches the glee squint")
        let dots = FaceProgramBuilder.program(for: .action(ActionFace(phase: .resting)), identity: identity)
        #expect(dots.color == Theme.actionColor && dots.pose == FaceProgramBuilder.resolved(.sleepy, identity))
        let config = FaceConfiguration(identity: identity, mode: .action(ActionFace(phase: .launching)), size: 44, filter: .none, satellites: 3)
        #expect(BlobLayerTree.satelliteCount(for: config) == 0, "action faces never orbit")
    }
}

@Suite("Action store")
@MainActor
struct ActionStoreTests {
    @Test("A missing file is created as an empty list; a change on disk reloads; a broken file keeps the last list")
    func defaultFileAndReload() async throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "nested/actions.json")
        let store = ActionStore(fileURL: file)
        defer { store.stop() }
        #expect(store.actions.isEmpty)
        store.start()
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: file, encoding: .utf8) == "[]\n", "no personal default action")
        #expect(store.actions.isEmpty && store.lastError == nil)
        #expect(try ActionItem.decode(Data(contentsOf: file)).isEmpty)

        let two = [ActionItem.standup, ActionItem(id: "second", name: "Second", cwd: "/tmp", prompt: "two")]
        // In place, like a plain write.
        try ActionItem.encode(two).write(to: file)
        #expect(await TestSupport.waitUntil(timeout: 2) { store.actions == two })

        // Atomic replace, like an editor's save.
        let one = [ActionItem(id: "only", name: "Only", cwd: "/tmp", prompt: "one")]
        try ActionItem.encode(one).write(to: file, options: .atomic)
        #expect(await TestSupport.waitUntil(timeout: 2) { store.actions == one })

        try Data("{ broken".utf8).write(to: file)
        #expect(await TestSupport.waitUntil(timeout: 2) { store.lastError != nil })
        #expect(store.actions == one, "the last good list stays")

        store.stop()
        store.start()
        #expect(store.actions == one, "start after stop is a no-op on the file")
    }

    @Test("Launch arguments: the actions file and the action hover target")
    func launchArguments() {
        let arguments = LaunchArguments(["app", "--actions-file", "/tmp/a.json", "--hover", "action:1"])
        #expect(arguments.actionsFile?.path == "/tmp/a.json")
        #expect(arguments.hover == .action(1))
        #expect(arguments.hover?.slotIndex(rowCount: 3) == 4)
        #expect(LaunchArguments.HoverTarget("2")?.slotIndex(rowCount: 3) == 2)
        #expect(LaunchArguments.HoverTarget("none")?.slotIndex(rowCount: 3) == nil)
        #expect(LaunchArguments.HoverTarget("action:x") == nil)
    }
}

/// Collects the window states a model asked for (a class so the closure can append).
@MainActor
private final class ActionWindowStateRecorder {
    var states: [PanelWindowState] = []
}

@Suite("Panel model with actions")
@MainActor
struct PanelActionTests {
    private let since = Date(timeIntervalSince1970: 1_700_000_000)

    /// Three live sessions and two actions; window calls are recorded.
    private func makeModel(sessions: Int = 3, actions: [ActionItem] = [.standup, ActionItem(id: "b", name: "B", cwd: "/tmp", prompt: "b")], expandMode: Theme.ExpandMode = .row) throws -> (SessionStore, ActionStore, PanelModel) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var records: [SessionRecord] = []
        for index in 0..<sessions {
            var record = try TestSupport.fixtureRecord(index == 0 ? "waiting-desktop" : index == 1 ? "busy-desktop" : "idle-desktop")
            record.pid = TestSupport.livePid + pid_t(index)
            records.append(record)
        }
        store.reconcile(RegistryScanResult(records: records, presentPids: Set(records.map(\.pid))))
        let folder = try TestSupport.makeTempFolder()
        let file = folder.appending(path: "actions.json")
        try ActionItem.encode(actions).write(to: file)
        let actionStore = ActionStore(fileURL: file)
        actionStore.start()
        let model = PanelModel(store: store, actionStore: actionStore, expandMode: expandMode)
        return (store, actionStore, model)
    }

    @Test("Capsule height: divider and action rows only with both sections; actions alone need no stub")
    func capsuleHeight() throws {
        let pitch = Theme.rowPitch
        let base = Theme.capsuleEndPadding * 2 + Theme.edgeFilletRadius * 2
        #expect(Theme.capsuleHeight(rows: 3) == Theme.capsuleHeight(rows: 3, actions: 0))
        #expect(Theme.capsuleHeight(rows: 3, actions: 0) == base + 3 * pitch)
        #expect(Theme.capsuleHeight(rows: 3, actions: 1) == base + 4 * pitch + Theme.dividerHeight)
        #expect(Theme.capsuleHeight(rows: 3, actions: 2) == base + 5 * pitch + Theme.dividerHeight)
        #expect(Theme.capsuleHeight(rows: 0, actions: 0) == base + pitch, "the empty stub")
        #expect(Theme.capsuleHeight(rows: 0, actions: 1) == base + pitch, "actions alone: no stub, no divider")
        #expect(Theme.capsuleHeight(rows: 0, actions: 2) == base + 2 * pitch)
        #expect(Theme.liveSlots(rows: 0, actions: 0) == 1 && Theme.liveSlots(rows: 0, actions: 2) == 0 && Theme.liveSlots(rows: 2, actions: 2) == 2)
        #expect(!Theme.hasDivider(rows: 0, actions: 2) && !Theme.hasDivider(rows: 2, actions: 0) && Theme.hasDivider(rows: 1, actions: 1))
        #expect(Theme.dividerHeight >= 12 && Theme.dividerHeight <= 16)

        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        #expect(model.actionRows.map(\.id) == ["standup", "b"])
        #expect(model.slotCount == 5 && model.hasDivider && model.capsuleRows == 3)
        #expect(model.capsuleHeight == Theme.capsuleHeight(rows: 3, actions: 2))
        #expect(model.capsuleBodyHeight == Theme.capsuleBodyHeight(rows: 3, actions: 2))

        let (emptyStore, emptyActions, onlyActions) = try makeModel(sessions: 0)
        defer { emptyStore.stop(); emptyActions.stop() }
        #expect(onlyActions.capsuleRows == 0 && !onlyActions.hasDivider && onlyActions.capsuleHeight == Theme.capsuleHeight(rows: 0, actions: 2))
        #expect(onlyActions.slotCenterY(slot: 0) == PanelModel.rowCenterY(index: 0), "the first action sits where the first row would")
    }

    @Test("Slot centres and the pointer maths across the divider")
    func slotGeometry() throws {
        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        let pitch = Theme.rowPitch
        let top = Theme.edgeFilletRadius + Theme.capsuleEndPadding
        #expect(model.slotCenterY(slot: 2) == PanelModel.rowCenterY(index: 2))
        #expect(model.slotCenterY(slot: 3) == PanelModel.rowCenterY(index: 3) + Theme.dividerHeight)
        #expect(model.slotCenterY(slot: 4) == PanelModel.rowCenterY(index: 4) + Theme.dividerHeight)
        #expect(PanelModel.slotCenterY(slot: 0, rows: 0, actions: 2) == PanelModel.rowCenterY(index: 0))

        let liveBottom = top + 3 * pitch
        #expect(model.rowIndex(atY: liveBottom - 1) == 2)
        #expect(model.rowIndex(atY: liveBottom + Theme.dividerHeight / 2 - 1) == 2, "upper half of the divider band belongs to the last row")
        #expect(model.rowIndex(atY: liveBottom + Theme.dividerHeight / 2 + 1) == 3, "lower half to the first action")
        #expect(model.rowIndex(atY: liveBottom + Theme.dividerHeight + 1) == 3)
        #expect(model.rowIndex(atY: liveBottom + Theme.dividerHeight + pitch + 1) == 4)
        #expect(model.rowIndex(atY: model.capsuleHeight) == 4, "the bottom fillet snaps to the last action")
        #expect(model.rowIndex(atY: model.capsuleHeight + 1) == nil)
        #expect(model.rowIndex(atY: top + 1) == 0)

        let (emptyStore, emptyActions, onlyActions) = try makeModel(sessions: 0)
        defer { emptyStore.stop(); emptyActions.stop() }
        #expect(onlyActions.rowIndex(atY: top + 1) == 0 && onlyActions.rowIndex(atY: top + pitch + 1) == 1)
    }

    @Test("Hovering an action row: expands, keeps the bulge on it, ends like a session hover; .all mode includes actions")
    func hoverActions() async throws {
        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        let recorder = ActionWindowStateRecorder()
        model.setWindowState = { recorder.states.append($0) }
        model.hover(rowIndex: 3)
        #expect(model.isExpanded && model.hoveredKey == nil && model.hoveredActionID == "standup")
        #expect(model.hoveredRowIndex == 3 && model.bulgeRowIndex == 3 && !model.bulgeTravelled)
        #expect(model.isActionExpanded("standup") && !model.isActionExpanded("b"))
        #expect(model.rows.allSatisfy { !model.isRowExpanded($0.key) })
        #expect(recorder.states == [.expanded(width: Theme.contentWidth)])
        let center = model.slotCenterY(slot: 3)
        #expect(model.hoverRegionContains(distanceFromEdge: Theme.capsuleWidth + 50, y: center) == .bulge)
        #expect(model.hoverRegionContains(distanceFromEdge: Theme.capsuleWidth + 50, y: center - Theme.rowPitch) == .outside)

        model.hover(rowIndex: 1)
        #expect(model.hoveredActionID == nil && model.hoveredKey == model.rows[1].key && model.bulgeTravelled)
        model.hover(rowIndex: 4)
        #expect(model.hoveredKey == nil && model.hoveredActionID == "b" && model.bulgeTravelled)
        model.hover(rowIndex: 5)
        #expect(!model.isExpanded && model.hoveredActionID == nil, "beyond the last slot ends the hover")

        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        model.pointerMoved(to: CGPoint(x: size.width - Theme.capsuleWidth / 2, y: model.slotCenterY(slot: 4)), in: size)
        #expect(model.hoveredActionID == "b")
        model.pointerMoved(to: nil, in: size)
        #expect(!model.isExpanded)

        let (allStore, allActions, all) = try makeModel(expandMode: .all)
        defer { allStore.stop(); allActions.stop() }
        all.hover(rowIndex: 0)
        #expect(all.isActionExpanded("standup") && all.isActionExpanded("b") && all.rows.allSatisfy { all.isRowExpanded($0.key) })
        all.hover(rowIndex: nil)
        #expect(!all.isActionExpanded("standup"))
    }

    @Test("Clicking an action runs it at once, squints, shows the cloud after the squint and drops it after the feedback")
    func tappedAction() async throws {
        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        var launched: [ActionItem] = []
        model.runAction = { item, _ in launched.append(item) }
        let row = model.actionRows[0]
        model.tappedAction(row)
        #expect(launched == [.standup])
        #expect(model.actionRows[0].squintToken == 1 && !model.actionRows[0].launching)
        #expect(await TestSupport.waitUntil(timeout: Theme.actionSquintDuration + 1) { model.actionRows[0].launching })
        #expect(model.actionRows[0].face(hovered: false).phase == .launching)
        #expect(await TestSupport.waitUntil(timeout: Theme.actionLaunchFeedback + 1) { !model.actionRows[0].launching })
        model.tappedAction(model.actionRows[0])
        #expect(model.actionRows[0].squintToken == 2 && launched.count == 2)
        model.tappedAction(ActionRow(item: ActionItem(id: "ghost", name: "G", cwd: "/", prompt: "g")))
        #expect(launched.count == 2, "an unknown action does nothing")
    }

    @Test("A prefill-only launch shows the Return hint in the bulge for a while; a sent launch shows none")
    func sendHint() async throws {
        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        func launches(reporting outcome: ActionLaunch.Report) {
            model.runAction = { _, report in report(outcome) }
        }
        launches(reporting: .sent)
        model.sendHintDuration = 0.3
        model.tappedAction(model.actionRows[0])
        #expect(model.actionRows[0].hint == nil)
        launches(reporting: .needsManualSend)
        model.tappedAction(model.actionRows[0])
        #expect(model.actionRows[0].hint == Theme.actionSendHint && model.actionRows[1].hint == nil)
        #expect(await TestSupport.waitUntil(timeout: 2) { model.actionRows[0].hint == nil })
        model.tappedAction(model.actionRows[0])
        launches(reporting: .sent)
        model.tappedAction(model.actionRows[0])
        #expect(model.actionRows[0].hint == nil, "a new click clears the old hint")
    }

    @Test("Layout changes: the window grows at once with actions, shrinks after the spring when actions leave; reorder resizes nothing")
    func layoutWithActions() async throws {
        let (store, actionStore, model) = try makeModel()
        defer { store.stop(); actionStore.stop() }
        var heights: [CGFloat] = []
        model.setWindowHeight = { heights.append($0) }
        model.layoutDidChange(rows: 3, actions: 2)
        #expect(heights == [Theme.capsuleHeight(rows: 3, actions: 2)])
        #expect(model.layoutAnimation(rowCount: 3, actionCount: 1) == RowEntrance.departureAnimation(reduceMotion: false), "a shrink runs on the departure progress")
        #expect(model.layoutAnimation(rowCount: 3, actionCount: 3) == Theme.openSpring)
        model.layoutDidChange(rows: 3, actions: 2)
        #expect(heights.count == 1, "same height, no resize")
        model.layoutDidChange(rows: 3, actions: 3)
        #expect(heights.last == Theme.capsuleHeight(rows: 3, actions: 3))
        model.layoutDidChange(rows: 3, actions: 1)
        #expect(heights.count == 2, "shrinking waits for the spring")
        #expect(await TestSupport.waitUntil(timeout: Theme.closeSpringSettleTime + 1) { heights.count == 3 })
        #expect(heights.last == Theme.capsuleHeight(rows: 3, actions: 1))
        model.rowCountDidChange(2)  // The row-only entry point still exists and counts the current actions.
        #expect(model.layoutAnimation(rowCount: 2, actionCount: 2) == Theme.openSpring)

        model.hover(rowIndex: 4)
        #expect(model.hoveredActionID == "b")
        try ActionItem.encode([.standup]).write(to: actionStore.fileURL)
        #expect(await TestSupport.waitUntil(timeout: 2) { model.actionRows.count == 1 })
        model.layoutDidChange(rows: 3, actions: 1)
        #expect(model.hoveredActionID == nil && !model.isExpanded, "the hovered action left, the hover ends")
    }
}
