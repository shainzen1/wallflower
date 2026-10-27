import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The Sound tab: which sound plays when a session is done or needs input (Wallflower ping, a
/// macOS system sound, a custom file, none), the volume with a preview, and the switches.
struct SoundSettingsView: View {
    @Bindable var settings: AppSettings
    let sounds: SoundController
    @Bindable var state: SoundViewState

    /// What the picker offers: a choice, or the "Choose File…" item, which opens a panel and leaves
    /// the selection as it was.
    enum MenuItem: Hashable {
        case choice(SoundChoice)
        case chooseFile
    }

    var body: some View {
        Form {
            Section {
                Picker("Sound", selection: menuSelection) {
                    Text(SoundChoice.wallflowerPing.settingsTitle).tag(MenuItem.choice(.wallflowerPing))
                    Divider()
                    ForEach(state.systemSounds, id: \.self) { name in
                        Text(name).tag(MenuItem.choice(.system(name)))
                    }
                    Divider()
                    if let name = settings.customSoundName {
                        Text(name).tag(MenuItem.choice(.custom))
                    }
                    Text("Choose File…").tag(MenuItem.chooseFile)
                    Divider()
                    Text(SoundChoice.none.settingsTitle).tag(MenuItem.choice(.none))
                }
                customFileRow
                if let problem = sounds.problem {
                    SettingsNote(text: problem.message) {}
                }
                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.soundVolume, in: 0...1) { editing in
                            // Released: hear the new level once.
                            if !editing { sounds.play() }
                        }
                        Text(settings.soundVolume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Button {
                            sounds.play()
                        } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                    }
                }
                .disabled(settings.sound == .none)
            } footer: {
                SettingsFootnote("A custom sound can be an AIFF, WAV, MP3, M4A or CAF file of up to 5 MB and 5 seconds. \(AppInfo.name) keeps its own copy, so you can move or delete the original.")
            }

            Section {
                Toggle("An agent is done (your turn)", isOn: $settings.soundOnDone)
                Toggle("An agent needs input", isOn: $settings.soundOnNeedsInput)
                Toggle("Not while the agent's app is in front", isOn: $settings.soundSkipsFrontmost)
            } header: {
                Text("Play the sound when")
            } footer: {
                SettingsFootnote("Only for changes while \(AppInfo.name) runs, never for sessions you threw out. Several changes within a second play one sound. Focus doesn't silence it.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// The custom file: its name, Choose File…, and a drop target for a file from the Finder.
    private var customFileRow: some View {
        LabeledContent("Custom sound") {
            HStack(spacing: 8) {
                Text(settings.customSoundName ?? "Drop a file here")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose File…", action: chooseFile)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(-4)
                .opacity(state.isDropTargeted ? 1 : 0)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            return sounds.installCustomSound(from: url) == nil ? playInstalled() : false
        } isTargeted: { targeted in
            state.isDropTargeted = targeted
        }
    }

    private var menuSelection: Binding<MenuItem> {
        Binding(
            get: { .choice(Self.shownChoice(settings.sound, customName: settings.customSoundName, systemSounds: state.systemSounds)) },
            set: { item in
                switch item {
                case .choice(let choice): settings.sound = choice
                case .chooseFile: chooseFile()
                }
            }
        )
    }

    /// The choice the picker shows: the ping for a custom sound without a file or a system sound this
    /// macOS lacks (what plays then, `SoundLibrary.url(for:customName:folder:)`).
    static func shownChoice(_ choice: SoundChoice, customName: String?, systemSounds: [String]) -> SoundChoice {
        switch choice {
        case .custom where customName == nil: .wallflowerPing
        case .system(let name) where !systemSounds.contains(name): .wallflowerPing
        default: choice
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = CustomSound.allowedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a sound of up to 5 seconds."
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                if sounds.installCustomSound(from: url) == nil { _ = playInstalled() }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// The new file plays once, so the person hears what they picked.
    private func playInstalled() -> Bool {
        sounds.play()
        return true
    }
}

/// View state of the Sound tab.
@Observable @MainActor
final class SoundViewState {
    /// The macOS system sounds, read once when the window opens.
    let systemSounds: [String]
    /// A file is dragged over the custom sound row.
    var isDropTargeted = false

    init(systemSounds: [String] = SoundLibrary.systemSoundNames()) {
        self.systemSounds = systemSounds
    }
}
