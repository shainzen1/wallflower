import Foundation
import Observation

/// The logic of the actions editor in Settings > General: the list, its selection, add, remove,
/// reorder, and the sheet that edits one action. Views only read it and call it, so everything here
/// is testable without a window.
///
/// `actions.json` stays the source of truth: every change writes the whole list through
/// `ActionStore.save` at once (the panel follows live), and a change made to the file by hand shows
/// up here through the store's reload (`sync()`). An existing action saves with every keystroke; a
/// new one is only a draft until "Add", which makes its id from the name (`ActionItem.makeID`).
@Observable @MainActor
final class ActionEditorModel {
    /// What the sheet edits: the fields of one action, as typed.
    struct Draft: Equatable {
        /// The action being edited, nil for a new one.
        var id: String?
        var name: String
        var cwd: String
        var prompt: String
        var days: [String]?

        /// A blank new action. The folder starts at the home folder, which always exists.
        static let blank = Draft(id: nil, name: "", cwd: "~", prompt: "", days: nil)

        init(id: String?, name: String, cwd: String, prompt: String, days: [String]?) {
            self.id = id
            self.name = name
            self.cwd = cwd
            self.prompt = prompt
            self.days = days
        }

        init(_ item: ActionItem) {
            self.init(id: item.id, name: item.name, cwd: item.cwd, prompt: item.prompt, days: item.days)
        }

        var isNew: Bool { id == nil }

        /// Name and folder are required; the prompt may be empty (plain `claude`).
        var isValid: Bool {
            !Self.trimmed(name).isEmpty && !Self.trimmed(cwd).isEmpty
        }

        /// `item` with these fields, trimmed. Everything the editor does not show (`seed`, `symbol`,
        /// `shape`, `color`) is kept.
        func applied(to item: ActionItem) -> ActionItem {
            var item = item
            item.name = Self.trimmed(name)
            item.cwd = Self.trimmed(cwd)
            item.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            item.days = ActionSchedule.storedDays(ActionSchedule.enabledDays(days))
            return item
        }

        static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// One line of the list, ready to show.
    struct Row: Equatable, Identifiable {
        var id: String
        var name: String
        /// The folder and the first line of the prompt.
        var detail: String
        /// "Every day" or the day names.
        var days: String
    }

    let store: ActionStore
    /// The selected action's id in the list.
    var selection: String?
    /// The row the list scrolls to (`scrollPosition(id:)`), set by `reveal()`. A click selects a row
    /// that is already in sight, so only the keys, the move buttons and a new action reveal.
    var scrollTarget: String?
    /// The sheet's fields; nil while the sheet is closed.
    private(set) var draft: Draft?
    /// The last save error, shown under the list; cleared by the next good save.
    private(set) var saveError: String?

    /// The edited action as last loaded or saved by the sheet, to tell a change made elsewhere apart
    /// from the sheet's own.
    @ObservationIgnored private var draftBase: ActionItem?

    /// Home folder for `~` (tests inject one).
    @ObservationIgnored let home: String

    /// Placeholder name of an action whose name was cleared (the list never shows an empty line).
    static let untitled = "Untitled action"
    /// Characters of the prompt shown in a list row.
    static let promptPreviewLength = 60

    init(store: ActionStore, home: String = NSHomeDirectory()) {
        self.store = store
        self.home = home
    }

    var items: [ActionItem] { store.actions }

    var rows: [Row] {
        items.map(Self.row)
    }

    static func row(for item: ActionItem) -> Row {
        let name = Draft.trimmed(item.name)
        return Row(
            id: item.id,
            name: name.isEmpty ? untitled : name,
            detail: [item.cwd, promptPreview(item.prompt)].filter { !$0.isEmpty }.joined(separator: "  ·  "),
            days: ActionSchedule.caption(item.days)
        )
    }

    /// The first non-empty line of `prompt`, cut at `promptPreviewLength` characters with an ellipsis.
    static func promptPreview(_ prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > promptPreviewLength else { return line }
        return String(line.prefix(promptPreviewLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return items.firstIndex { $0.id == selection }
    }

    var canRemove: Bool { selectedIndex != nil }
    var canEdit: Bool { selectedIndex != nil }
    var canMoveUp: Bool { selectedIndex.map { $0 > 0 } ?? false }
    var canMoveDown: Bool { selectedIndex.map { $0 < items.count - 1 } ?? false }

    // MARK: Sheet

    /// Opens the sheet on a blank new action.
    func startAdding() {
        draft = .blank
    }

    /// Opens the sheet on the action `id` (the selection when nil).
    func startEditing(_ id: String? = nil) {
        guard let id = id ?? selection, let item = items.first(where: { $0.id == id }) else { return }
        selection = id
        draft = Draft(item)
        draftBase = item
    }

    /// Whether the sheet's button (Add, Done) may close it.
    var canFinish: Bool { draft?.isValid ?? false }

    /// Add for a new action (saves it with a fresh id and selects it), Done for an existing one
    /// (already saved). Does nothing while a required field is blank.
    func finish() {
        guard let draft, draft.isValid else { return }
        if draft.isNew {
            let id = ActionItem.makeID(for: Draft.trimmed(draft.name), existing: items.map(\.id))
            let item = draft.applied(to: ActionItem(id: id, name: "", cwd: "", prompt: ""))
            guard save(items + [item]) else { return }
            selection = id
            reveal()
        }
        close()
    }

    /// Closes the sheet. A new action is dropped; an existing one keeps what was saved.
    func cancel() {
        close()
    }

    private func close() {
        draft = nil
        draftBase = nil
    }

    func setName(_ name: String) { edit { $0.name = name } }
    func setFolder(_ cwd: String) { edit { $0.cwd = cwd } }
    func setPrompt(_ prompt: String) { edit { $0.prompt = prompt } }

    /// Flips one weekday; the last day that is on stays on (`ActionSchedule.toggling`).
    func toggleDay(_ key: String) {
        edit { $0.days = ActionSchedule.toggling(key, in: $0.days) }
    }

    /// The folder picked in the open panel, written short (`~/notes`).
    func chooseFolder(_ url: URL) {
        setFolder(Self.displayPath(url.path, home: home))
    }

    /// `path` with the home folder written as `~`.
    static func displayPath(_ path: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        if path == home { return "~" }
        if home.count > 1, path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The folder to open the panel in: the draft's folder with `~` expanded, when it is set.
    var folderPanelStart: URL? {
        guard let cwd = draft.map({ Draft.trimmed($0.cwd) }), !cwd.isEmpty else { return nil }
        let expanded = cwd == "~" ? home : (cwd.hasPrefix("~/") ? home + cwd.dropFirst(1) : cwd)
        return URL(filePath: expanded, directoryHint: .isDirectory)
    }

    /// Changes the draft; an existing action is saved at once (blank required fields are not saved,
    /// the file keeps the last good value until the field is filled in again).
    private func edit(_ change: (inout Draft) -> Void) {
        guard var draft else { return }
        change(&draft)
        self.draft = draft
        guard let id = draft.id, draft.isValid else { return }
        var list = items
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let updated = draft.applied(to: list[index])
        guard updated != list[index] else { return }
        list[index] = updated
        if save(list) { draftBase = updated }
    }

    // MARK: List

    /// Removes the selected action; the selection moves to the next one (or the one before the end).
    func removeSelected() {
        guard let index = selectedIndex else { return }
        remove(at: index)
    }

    /// Removes the action `id`.
    func remove(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        remove(at: index)
    }

    private func remove(at index: Int) {
        var list = items
        let removed = list.remove(at: index)
        guard save(list) else { return }
        if draft?.id == removed.id { close() }
        if selection == removed.id {
            selection = list.isEmpty ? nil : list[min(index, list.count - 1)].id
        }
    }

    /// Drag and drop in the list (`ForEach.onMove`).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = items
        list.move(fromOffsets: source, toOffset: destination)
        guard list != items else { return }
        save(list)
    }

    /// Drag and drop onto a row: the dragged action takes the place of `targetID`, the rows between
    /// shift by one. Returns whether anything moved.
    @discardableResult
    func moveItem(_ id: String, to targetID: String) -> Bool {
        var list = items
        guard let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == targetID }), from != to else { return false }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        return save(list)
    }

    /// The arrow keys: select the row above or below (the first or last one when nothing is selected).
    func selectPrevious() { stepSelection(by: -1) }
    func selectNext() { stepSelection(by: 1) }

    private func stepSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        if let index = selectedIndex {
            selection = items[max(0, min(items.count - 1, index + offset))].id
        } else {
            selection = (offset > 0 ? items.first : items.last)?.id
        }
        reveal()
    }

    /// Scrolls the list to the selected row.
    func reveal() {
        if let selection { scrollTarget = selection }
    }

    func moveSelectedUp() { moveSelected(by: -1) }
    func moveSelectedDown() { moveSelected(by: 1) }

    private func moveSelected(by offset: Int) {
        guard let index = selectedIndex else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        var list = items
        list.swapAt(index, target)
        if save(list) { reveal() }
    }

    /// Follows a change of the file made elsewhere: a selection or an edited action that is gone is
    /// dropped, and the sheet takes over an edited action's new values (unless they are what the
    /// sheet itself saved, so typing is never undone).
    func sync() {
        if let selection, !items.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        guard let draft, let id = draft.id else { return }
        guard let item = items.first(where: { $0.id == id }) else {
            close()
            return
        }
        guard item != draftBase else { return }
        self.draft = Draft(item)
        draftBase = item
    }

    @discardableResult
    private func save(_ list: [ActionItem]) -> Bool {
        do {
            try store.save(list)
            if saveError != nil { saveError = nil }
            return true
        } catch {
            saveError = error.localizedDescription
            NSLog("%@: could not save actions.json: %@", AppInfo.name, error.localizedDescription)
            return false
        }
    }
}
