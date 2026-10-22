import AppKit
import SwiftUI

/// The Actions section of Settings > General: the list of action faces with add, remove and reorder,
/// a sheet that edits one action, a small link to the JSON file, and the launcher choice. The logic
/// lives in `ActionEditorModel`.
struct ActionsSettingsSection: View {
    @Bindable var settings: AppSettings
    let accessibility: AccessibilityAccess
    let actions: SettingsActions
    /// The editor; nil shows the launcher choice only.
    var editor: ActionEditorModel?

    var body: some View {
        Section {
            LabeledContent {
                Button("Edit JSON…", action: actions.editActions)
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .help("Open actions.json in your text editor")
            } label: {
                Text("Action faces")
                Text("Start a new Claude session with a saved prompt.")
            }
            if let editor {
                ActionListView(model: editor, launcher: settings.actionLauncher)
            }
        } header: {
            Text("Actions")
        }

        Section {
            Picker("Run actions in", selection: $settings.actionLauncher) {
                ForEach(Theme.ActionLauncher.settingsChoices, id: \.self) { Text($0.settingsTitle).tag($0) }
            }
            if settings.actionLauncher.needsAccessibility {
                LabeledContent {
                    if !accessibility.isTrusted {
                        Button("Open Accessibility Settings") { accessibility.openSettings() }
                    }
                } label: {
                    Text("Sending prompts")
                    Text(accessibility.isTrusted ? "Allowed" : "Not allowed")
                }
            }
        } footer: {
            SettingsFootnote(settings.actionLauncher.needsAccessibility
                ? "The Claude app can only prefill a prompt. \(AppInfo.name) presses Return for you, which needs Accessibility."
                : "Runs claude in the action's folder in a background Terminal window.")
        }
    }
}

/// The list of actions in file order with a button bar below it (add, remove, move up, move down,
/// edit). Click selects, double-click or Return edits, Delete removes, the arrow keys move the
/// selection, and a row can be dragged onto another to take its place. Up to `visibleRows` rows show
/// at once; a longer list scrolls inside, so the window stays short.
///
/// A `ScrollView` with `scrollPosition(id:)`, not a `List`: nested in the grouped `Form`, neither a
/// `List` nor a `ScrollView` moved for `ScrollViewProxy.scrollTo` (measured: the clip view's origin
/// stayed at 0), so a new or moved action could end up out of sight. `scrollPosition(id:)` scrolls.
struct ActionListView: View {
    @Bindable var model: ActionEditorModel
    /// How actions run, for the sheet's note on the model fields.
    var launcher: Theme.ActionLauncher = Theme.actionLauncher

    static let rowHeight: CGFloat = 44
    static let visibleRows = 4

    /// Height of the list: one row for the empty note, up to `visibleRows`, and half a row more when it
    /// scrolls, so the cut-off row tells there is more.
    static func listHeight(rows: Int) -> CGFloat {
        rowHeight * CGFloat(min(max(rows, 1), visibleRows)) + (rows > visibleRows ? rowHeight / 2 : 0)
    }

    var body: some View {
        let rows = model.rows
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        ActionListRow(
                            row: row, isSelected: model.selection == row.id, showsDivider: row.id != rows.last?.id
                        )
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.startEditing(row.id) }
                        .simultaneousGesture(TapGesture().onEnded { model.selection = row.id })
                        .contextMenu {
                            Button("Edit…") { model.startEditing(row.id) }
                            Button("Remove") { model.remove(row.id) }
                        }
                        .draggable(row.id)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first else { return false }
                            return model.moveItem(id, to: row.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: Binding(get: { model.scrollTarget }, set: { model.scrollTarget = $0 }), anchor: .center)
            .scrollDisabled(rows.count <= Self.visibleRows)
            .frame(height: Self.listHeight(rows: rows.count))
            .overlay {
                if rows.isEmpty {
                    Text("No actions yet. Click + to add one.")
                        .foregroundStyle(.secondary)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: model.selectPrevious()
                case .down: model.selectNext()
                default: break
                }
            }
            .onDeleteCommand { model.removeSelected() }
            .onKeyPress(.return) {
                guard model.canEdit else { return .ignored }
                model.startEditing()
                return .handled
            }

            Divider()
            ActionListBar(model: model)
            if let error = model.saveError {
                SettingsNote(text: "Could not save actions.json: \(error)") { EmptyView() }
                    .padding(.top, 6)
            }
        }
        .onChange(of: model.items) { model.sync() }
        .sheet(isPresented: Binding(get: { model.draft != nil }, set: { if !$0 { model.cancel() } })) {
            ActionEditorSheet(model: model, launcher: launcher)
        }
    }
}

/// One row: the name and the caption (days, model, effort) on the first line, the folder and the start of the prompt below.
/// Selected, it fills with the selection colour (muted while the window is in the background).
private struct ActionListRow: View {
    let row: ActionEditorModel.Row
    let isSelected: Bool
    let showsDivider: Bool
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.caption)
                    .font(.caption)
                    .foregroundStyle(secondaryStyle)
                    .lineLimit(1)
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(secondaryStyle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isSelected && appearsActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor))
            }
        }
        .overlay(alignment: .bottom) {
            if showsDivider, !isSelected {
                Divider().padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var secondaryStyle: AnyShapeStyle {
        isSelected && appearsActive ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)
    }
}

/// Small borderless buttons under the list, in the macOS add and remove bar style.
private struct ActionListBar: View {
    let model: ActionEditorModel

    var body: some View {
        HStack(spacing: 2) {
            barButton("plus", help: "Add an action") { model.startAdding() }
            barButton("minus", help: "Remove the selected action") { model.removeSelected() }
                .disabled(!model.canRemove)
            Divider().frame(height: 14).padding(.horizontal, 4)
            barButton("chevron.up", help: "Move up") { model.moveSelectedUp() }
                .disabled(!model.canMoveUp)
            barButton("chevron.down", help: "Move down") { model.moveSelectedDown() }
                .disabled(!model.canMoveDown)
            Spacer()
            Button("Edit…") { model.startEditing() }
                .controlSize(.small)
                .disabled(!model.canEdit)
        }
        .padding(.top, 6)
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The sheet for one action: name, folder (typed or chosen), prompt, weekdays, then the model and
/// effort of the session. An existing action saves as you type and closes with Done; a new one is
/// added with Add (or dropped with Cancel).
struct ActionEditorSheet: View {
    let model: ActionEditorModel
    /// How actions run: the Claude app gets a note that it ignores the model fields.
    var launcher: Theme.ActionLauncher = Theme.actionLauncher

    static let width: CGFloat = 460

    var body: some View {
        let draft = model.draft ?? .blank
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: Binding(get: { model.draft?.name ?? "" }, set: { model.setName($0) }),
                              prompt: Text("Standup notes"))
                    LabeledContent("Folder") {
                        HStack(spacing: 6) {
                            TextField("Folder", text: Binding(get: { model.draft?.cwd ?? "" }, set: { model.setFolder($0) }),
                                      prompt: Text("~/notes"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                        TextField("Prompt", text: Binding(get: { model.draft?.prompt ?? "" }, set: { model.setPrompt($0) }),
                                  prompt: Text("Write today's standup notes from yesterday's commits"), axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }
                    LabeledContent {
                        WeekdayToggles(days: draft.days) { model.toggleDay($0) }
                    } label: {
                        Text("Days")
                        Text(ActionSchedule.caption(draft.days))
                    }
                } header: {
                    Text(draft.isNew ? "New action" : "Edit action")
                }

                Section {
                    Picker("Model", selection: Binding(get: { model.draft?.modelChoice ?? .standard }, set: { model.setModelChoice($0) })) {
                        Text(ActionEditorModel.ModelChoice.standard.title).tag(ActionEditorModel.ModelChoice.standard)
                        Divider()
                        ForEach(ActionEditorModel.ModelChoice.aliases) { Text($0.title).tag($0) }
                        Divider()
                        Text(ActionEditorModel.ModelChoice.custom.title).tag(ActionEditorModel.ModelChoice.custom)
                    }
                    if draft.modelChoice == .custom {
                        TextField("Model id", text: Binding(get: { model.draft?.customModel ?? "" }, set: { model.setCustomModel($0) }),
                                  prompt: Text("claude-sonnet-5-5"))
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Effort", selection: Binding(get: { model.draft?.effortChoice }, set: { model.setEffort($0) })) {
                        Text("Default").tag(ClaudeEffort?.none)
                        Divider()
                        ForEach(ClaudeEffort.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                } footer: {
                    SettingsFootnote(footnote(isNew: draft.isNew))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                if draft.isNew {
                    Button("Cancel", role: .cancel) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add") { model.finish() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canFinish)
                } else {
                    Button("Done") { model.finish() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canFinish)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: Self.width)
    }

    /// The model note (Claude app only), then how the sheet saves.
    private func footnote(isNew: Bool) -> String {
        let saving = isNew ? "The prompt runs as the first message, slash commands included." : "Changes are saved as you type."
        return [ActionEditorModel.modelNote(for: launcher), saving].compactMap { $0 }.joined(separator: "\n")
    }

    /// The open panel for a folder; the choice is written short (`~/...`).
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "The folder the session starts in."
        if let start = model.folderPanelStart { panel.directoryURL = start }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseFolder(url)
    }
}
