import SwiftUI

/// The General tab: launch at login, updates, which Claude sessions to show, the new session button, the
/// panel position and when it hides, the action faces. Sessions from other tools are on the Agents tab.
struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLogin
    /// The updater; nil (or not running) shows the update controls disabled.
    var updater: AppUpdater?
    let accessibility: AccessibilityAccess
    let actions: SettingsActions
    /// The actions editor; nil shows no list.
    var actionEditor: ActionEditorModel?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.set($0) }
                ))
                if let note = launchAtLogin.note {
                    SettingsNote(text: note) {
                        if launchAtLogin.needsApproval {
                            Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                        }
                    }
                }
            }

            updatesSection

            Section {
                Picker("Show sessions from", selection: $settings.sessionSource) {
                    ForEach(SessionSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
            } footer: {
                SettingsFootnote(settings.sessionSource == .desktop
                    ? "Clicking a face opens its chat in the Claude app."
                    : "Clicking a terminal session brings its terminal app to the front.")
            }

            Section {
                Toggle("New session button", isOn: $settings.newSessionButton)
            } footer: {
                SettingsFootnote(NewSessionLaunch.route(for: settings.sessionSource) == .claudeApp
                    ? "A plus at the top of the column starts a new chat in the Claude app."
                    : "A plus at the top of the column runs claude in your home folder in a background Terminal window.")
            }

            Section {
                Picker("Panel side", selection: $settings.panelSide) {
                    ForEach(PanelSide.settingsChoices, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Panel position") {
                    Button("Reset position", action: actions.resetPosition)
                }
                Picker("Hide the panel", selection: $settings.panelAutoHide) {
                    ForEach(PanelAutoHide.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                SettingsFootnote(["Drag the column along the edge to move it.", settings.panelAutoHide.footnote].compactMap { $0 }.joined(separator: " "))
            }

            ActionsSettingsSection(settings: settings, accessibility: accessibility, actions: actions, editor: actionEditor)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// "Check for updates automatically" (weekly, Sparkle's setting) and "Check Now" with the last check.
    private var updatesSection: some View {
        let running = updater?.isRunning == true
        return Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater?.automaticallyChecks == true },
                set: { updater?.setAutomaticallyChecks($0) }
            ))
            .disabled(!running)
            LabeledContent {
                Button("Check Now") { updater?.checkForUpdates() }
                    .disabled(updater?.canCheckForUpdates != true)
            } label: {
                Text(AppUpdater.lastCheckText(updater?.lastCheckDate, offReason: updater.map(\.offReason) ?? .scriptedLaunch))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } footer: {
            SettingsFootnote(Self.updatesFootnote)
        }
    }

    /// What the weekly check sends, in the words of the README's Privacy section.
    static let updatesFootnote = "Once a week \(AppInfo.name) asks GitHub whether a newer version is out. It sends no system profile and nothing else."
}

/// Secondary text under a section, aligned with the section's content.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An inline note row inside a section: an info symbol, the text, an optional trailing button.
struct SettingsNote<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .font(.callout)
    }
}
