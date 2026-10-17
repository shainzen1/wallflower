import Foundation
import Testing
@testable import AgentOverview

@Suite("Action ids")
struct ActionIDTests {
    @Test("Slugs: lowercase ASCII letters and digits, one dash between words, nothing else")
    func slugRules() {
        #expect(ActionItem.slug(for: "Standup notes") == "standup-notes")
        #expect(ActionItem.slug(for: "  Review   open PRs!! ") == "review-open-prs")
        #expect(ActionItem.slug(for: "/review") == "review", "no dash at the start")
        #expect(ActionItem.slug(for: "Release 2.0 notes") == "release-2-0-notes")
        #expect(ActionItem.slug(for: "Café Crème") == "cafe-creme", "diacritics folded")
        #expect(ActionItem.slug(for: "Straße") == "strasse")
        #expect(ActionItem.slug(for: "CamelCase") == "camelcase")
        #expect(ActionItem.slug(for: "🚀 🔥") == ActionItem.idFallback, "nothing usable left")
        #expect(ActionItem.slug(for: "") == "action" && ActionItem.idFallback == "action")

        let pattern = /^[a-z0-9]+(-[a-z0-9]+)*$/
        let names = ["日報", "Обзор кода", "a\u{2014}b", "x_y.z", "  --  ", String(repeating: "word ", count: 20)]
        for name in names {
            let slug = ActionItem.slug(for: name)
            #expect(slug.wholeMatch(of: pattern) != nil, "\(name) gave \(slug)")
            #expect(slug.count <= ActionItem.idSlugLimit)
        }
        #expect(ActionItem.slug(for: "日報") != ActionItem.idFallback, "other scripts are transliterated")
        let long = ActionItem.slug(for: "Draft the release notes for everything merged since the last tag")
        #expect(long.count <= ActionItem.idSlugLimit && !long.hasSuffix("-") && long.hasPrefix("draft-the-release-notes"))
    }

    @Test("Ids are unique: a taken slug gets -2, -3, compared without regard to case")
    func uniqueness() {
        #expect(ActionItem.makeID(for: "Standup notes", existing: []) == "standup-notes")
        #expect(ActionItem.makeID(for: "Standup notes", existing: ["standup-notes"]) == "standup-notes-2")
        #expect(ActionItem.makeID(for: "Standup notes", existing: ["standup-notes", "standup-notes-2"]) == "standup-notes-3")
        #expect(ActionItem.makeID(for: "Standup notes", existing: ["standup-notes-2"]) == "standup-notes")
        #expect(ActionItem.makeID(for: "review", existing: ["Review"]) == "review-2", "one launch file on a case-insensitive disk")
        #expect(ActionItem.makeID(for: "!!!", existing: ["action"]) == "action-2")
    }
}

/// An editor on a store whose file lives in a fresh temp folder.
@MainActor
private struct EditorFixture {
    let folder: URL
    let store: ActionStore
    let model: ActionEditorModel

    init(_ items: [ActionItem] = []) throws {
        folder = try TestSupport.makeTempFolder()
        store = ActionStore(fileURL: folder.appending(path: "actions.json", directoryHint: .notDirectory))
        try store.save(items)
        model = ActionEditorModel(store: store, home: "/Users/demo")
    }

    /// What a fresh read of the file gives: the file is the source of truth.
    func fileItems() throws -> [ActionItem] {
        try ActionItem.decode(Data(contentsOf: store.fileURL))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

private extension ActionItem {
    static let notes = ActionItem(id: "standup-notes", name: "Standup notes", cwd: "~/notes", prompt: "Write today's standup notes")
    static let review = ActionItem(id: "review", name: "Review open PRs", cwd: "~/projects/app", prompt: "/review")
    static let release = ActionItem(
        id: "release", name: "Release notes", cwd: "~/projects/app", prompt: "Draft release notes", seed: "s", shape: "cloud",
        color: "#7FD1B9", days: ["fri"]
    )
}

@Suite("Actions editor")
@MainActor
struct ActionEditorTests {
    @Test("Add: a draft until Add, then saved with an id from its name, selected and revealed")
    func add() throws {
        let fixture = try EditorFixture([.notes])
        defer { fixture.remove() }
        let model = fixture.model

        model.startAdding()
        #expect(model.draft == .blank && model.draft?.isNew == true && model.draft?.cwd == "~")
        #expect(!model.canFinish, "a name is required")
        model.setName("  Standup notes ")
        model.setPrompt("/standup\n")
        model.toggleDay("sat")
        model.toggleDay("sun")
        #expect(fixture.store.actions == [.notes], "nothing is saved before Add")
        #expect(model.canFinish)

        model.finish()
        #expect(model.draft == nil)
        let added = ActionItem(
            id: "standup-notes-2", name: "Standup notes", cwd: "~", prompt: "/standup", days: ["mon", "tue", "wed", "thu", "fri"]
        )
        #expect(fixture.store.actions == [.notes, added], "trimmed, a unique id, appended")
        #expect(try fixture.fileItems() == [.notes, added])
        #expect(model.selection == "standup-notes-2" && model.scrollTarget == "standup-notes-2")

        model.startAdding()
        model.setName("Gone")
        model.cancel()
        #expect(model.draft == nil && fixture.store.actions.count == 2, "Cancel drops a new action")

        model.startAdding()
        model.setName("No folder")
        model.setFolder("   ")
        #expect(!model.canFinish, "a folder is required")
        model.finish()
        #expect(model.draft != nil && fixture.store.actions.count == 2)
    }

    @Test("Edit: every change saves at once, the id never changes, blank fields are not saved, other keys stay")
    func edit() throws {
        let fixture = try EditorFixture([.notes, .release])
        defer { fixture.remove() }
        let model = fixture.model

        model.startEditing("release")
        #expect(model.selection == "release" && model.draft?.id == "release" && model.draft?.isNew == false)
        model.setName("Weekly release notes")
        #expect(fixture.store.actions[1].name == "Weekly release notes" && fixture.store.actions[1].id == "release")
        #expect(try fixture.fileItems()[1].name == "Weekly release notes", "saved as typed, no Done needed")

        model.setName("")
        #expect(model.draft?.name == "" && !model.canFinish)
        #expect(fixture.store.actions[1].name == "Weekly release notes", "a blank name is not saved")
        model.setName("Release notes ")
        model.setFolder("~/projects/other")
        model.setPrompt("Draft release notes\nfor the last tag")
        model.toggleDay("thu")
        let saved = fixture.store.actions[1]
        #expect(saved.name == "Release notes" && saved.cwd == "~/projects/other" && saved.prompt == "Draft release notes\nfor the last tag")
        #expect(saved.days == ["thu", "fri"])
        #expect(saved.seed == "s" && saved.shape == "cloud" && saved.color == "#7FD1B9", "keys the editor does not show are kept")
        #expect(model.draft?.name == "Release notes ", "the field keeps what was typed")

        model.toggleDay("thu")
        model.toggleDay("fri")
        #expect(fixture.store.actions[1].days == ["fri"], "the last day stays on")
        model.chooseFolder(URL(filePath: "/Users/demo/notes", directoryHint: .isDirectory))
        #expect(model.draft?.cwd == "~/notes" && fixture.store.actions[1].cwd == "~/notes")

        model.finish()
        #expect(model.draft == nil && model.selection == "release")
        #expect(try fixture.fileItems() == fixture.store.actions)
        #expect(fixture.store.actions.map(\.id) == ["standup-notes", "release"])
    }

    @Test("Reorder: move up and down, drag and drop, offsets; the file follows")
    func reorder() throws {
        let fixture = try EditorFixture([.notes, .review, .release])
        defer { fixture.remove() }
        let model = fixture.model
        func ids() throws -> [String] {
            let ids = fixture.store.actions.map(\.id)
            #expect(try fixture.fileItems().map(\.id) == ids)
            return ids
        }

        #expect(!model.canMoveUp && !model.canMoveDown && !model.canRemove && !model.canEdit, "nothing selected")
        model.selection = "release"
        #expect(model.canMoveUp && !model.canMoveDown)
        model.moveSelectedUp()
        #expect(try ids() == ["standup-notes", "release", "review"])
        #expect(model.selection == "release" && model.scrollTarget == "release", "the moved row stays selected and in sight")
        model.moveSelectedUp()
        model.moveSelectedUp()
        #expect(try ids() == ["release", "standup-notes", "review"], "the top row stays on top")
        model.moveSelectedDown()
        #expect(try ids() == ["standup-notes", "release", "review"])

        #expect(model.moveItem("standup-notes", to: "review"))
        #expect(try ids() == ["release", "review", "standup-notes"], "dropped onto a row, it takes that row's place")
        #expect(model.moveItem("standup-notes", to: "release"))
        #expect(try ids() == ["standup-notes", "release", "review"])
        #expect(!model.moveItem("standup-notes", to: "standup-notes") && !model.moveItem("dragged text", to: "review"))

        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(try ids() == ["release", "review", "standup-notes"])
    }

    @Test("Remove: the selection moves to the next row, or the one before at the end; an open sheet closes")
    func remove() throws {
        let fixture = try EditorFixture([.notes, .review, .release])
        defer { fixture.remove() }
        let model = fixture.model

        model.selection = "review"
        model.removeSelected()
        #expect(fixture.store.actions.map(\.id) == ["standup-notes", "release"] && model.selection == "release")
        model.startEditing("release")
        model.removeSelected()
        #expect(model.draft == nil && model.selection == "standup-notes", "the sheet of a removed action closes")
        model.remove("standup-notes")
        #expect(fixture.store.actions.isEmpty && model.selection == nil)
        #expect(try fixture.fileItems().isEmpty)
    }

    @Test("Round trip: add, edit, reorder and remove, then a fresh store reads the same list")
    func roundTrip() throws {
        let fixture = try EditorFixture()
        defer { fixture.remove() }
        let model = fixture.model

        for name in ["Standup notes", "Review open PRs", "Standup notes"] {
            model.startAdding()
            model.setName(name)
            model.setFolder("~/notes")
            model.setPrompt("Prompt for \(name)")
            model.finish()
        }
        #expect(fixture.store.actions.map(\.id) == ["standup-notes", "review-open-prs", "standup-notes-2"])
        model.startEditing("standup-notes-2")
        model.setName("Evening notes")
        model.finish()
        #expect(model.selection == "standup-notes-2", "renaming keeps the id")
        model.moveSelectedUp()
        model.selection = "standup-notes"
        model.removeSelected()

        let fresh = ActionStore(fileURL: fixture.store.fileURL)
        fresh.reload()
        #expect(fresh.lastError == nil)
        #expect(fresh.actions == fixture.store.actions)
        #expect(fresh.actions.map(\.id) == ["standup-notes-2", "review-open-prs"])
        #expect(fresh.actions.map(\.name) == ["Evening notes", "Review open PRs"])
    }

    @Test("Sync: a change made in the file reaches the sheet; the sheet's own saves never undo typing")
    func sync() throws {
        let fixture = try EditorFixture([.notes, .review])
        defer { fixture.remove() }
        let model = fixture.model

        model.startEditing("standup-notes")
        model.setName("Standup notes ")
        model.sync()
        #expect(model.draft?.name == "Standup notes ", "its own save (trimmed) does not reset the field")
        model.setName("")
        model.sync()
        #expect(model.draft?.name == "", "a blank field is kept while the file is unchanged")

        var edited = fixture.store.actions
        edited[0].prompt = "Edited by hand"
        try fixture.store.save(edited)
        model.sync()
        #expect(model.draft?.prompt == "Edited by hand" && model.draft?.name == "Standup notes", "taken over from the file")

        model.selection = "review"
        try fixture.store.save([.notes])
        model.sync()
        #expect(model.selection == nil, "a selection that left the file is dropped")
        #expect(model.draft?.id == "standup-notes")
        try fixture.store.save([.review])
        model.sync()
        #expect(model.draft == nil, "the sheet of an action that left the file closes")
    }

    @Test("Rows: name, days, folder and the first line of the prompt; arrow keys step the selection")
    func rows() throws {
        let long = String(repeating: "x", count: ActionEditorModel.promptPreviewLength + 10)
        let fixture = try EditorFixture([
            .release,
            ActionItem(id: "blank", name: "  ", cwd: "~", prompt: "\n  first line  \nsecond"),
            ActionItem(id: "long", name: "Long", cwd: "", prompt: long),
        ])
        defer { fixture.remove() }
        let model = fixture.model

        #expect(model.rows == [
            ActionEditorModel.Row(id: "release", name: "Release notes", detail: "~/projects/app  ·  Draft release notes", days: "Fri"),
            ActionEditorModel.Row(id: "blank", name: ActionEditorModel.untitled, detail: "~  ·  first line", days: "Every day"),
            ActionEditorModel.Row(
                id: "long", name: "Long", detail: String(repeating: "x", count: ActionEditorModel.promptPreviewLength) + "…", days: "Every day"
            ),
        ])

        model.selectNext()
        #expect(model.selection == "release" && model.scrollTarget == "release", "nothing selected: down picks the first")
        model.selectNext()
        model.selectNext()
        model.selectNext()
        #expect(model.selection == "long" && model.scrollTarget == "long", "stops at the end")
        model.selectPrevious()
        #expect(model.selection == "blank")
        model.selection = nil
        model.selectPrevious()
        #expect(model.selection == "long", "nothing selected: up picks the last")
        model.startEditing()
        #expect(model.draft?.id == "long", "Edit… opens the selection")
    }

    @Test("Folders: the home folder is written as ~, and expanded again for the open panel")
    func folders() throws {
        let home = "/Users/demo"
        #expect(ActionEditorModel.displayPath("/Users/demo/notes", home: home) == "~/notes")
        #expect(ActionEditorModel.displayPath("/Users/demo", home: home) == "~")
        #expect(ActionEditorModel.displayPath("/Users/demo2/notes", home: home) == "/Users/demo2/notes", "a sibling is not home")
        #expect(ActionEditorModel.displayPath("/tmp/x", home: home) == "/tmp/x")
        #expect(ActionEditorModel.displayPath("/Users/demo/a b", home: home + "/") == "~/a b", "a trailing slash on home is ignored")

        let fixture = try EditorFixture([.notes])
        defer { fixture.remove() }
        let model = fixture.model
        #expect(model.folderPanelStart == nil, "no sheet open")
        model.startEditing("standup-notes")
        #expect(model.folderPanelStart?.path == "/Users/demo/notes")
        model.setFolder("~")
        #expect(model.folderPanelStart?.path == "/Users/demo")
        model.setFolder("/tmp/work")
        #expect(model.folderPanelStart?.path == "/tmp/work")
    }

    @Test("Settings layout: the list shows at most four rows and a half; --edit-action parses")
    func layoutAndArguments() {
        #expect(ActionListView.listHeight(rows: 0) == ActionListView.rowHeight, "room for the empty note")
        #expect(ActionListView.listHeight(rows: 3) == 3 * ActionListView.rowHeight)
        #expect(ActionListView.listHeight(rows: 4) == 4 * ActionListView.rowHeight)
        #expect(ActionListView.listHeight(rows: 5) == 4.5 * ActionListView.rowHeight)
        #expect(ActionListView.listHeight(rows: 40) == ActionListView.listHeight(rows: 5), "a long list scrolls instead")

        #expect(LaunchArguments(["app", "--edit-action", "new"]).editAction == .new)
        #expect(LaunchArguments(["app", "--edit-action", "2"]).editAction == .edit(2))
        #expect(LaunchArguments(["app", "--edit-action", "select:1"]).editAction == .select(1))
        #expect(LaunchArguments(["app", "--edit-action", "-1"]).editAction == nil)
        #expect(LaunchArguments(["app", "--edit-action", "select:x"]).editAction == nil)
    }
}
