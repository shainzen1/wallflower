import SwiftUI

/// "Pick a sound": the sound with Preview, the volume, and the two moments it plays for, each beside
/// its face. The same settings as Settings > Sound, written as they change (`WelcomeModel.sound`);
/// the custom file and "Not while the agent's app is in front" stay in Settings. Nothing plays when
/// the page opens, only on Preview, a picked sound or a volume let go.
struct WelcomeSoundPage: View {
    @Bindable var model: WelcomeModel
    /// Coloured by status, so the two faces are the lime and the amber of "Shape is status".
    var look: PanelLook

    private var isSilent: Bool { model.sound.sound == .none }

    var body: some View {
        VStack(spacing: 0) {
            WelcomeTitle("Pick a sound")
            VStack(spacing: 0) {
                WelcomeChoiceRow(title: "Sound") {
                    HStack(spacing: 8) {
                        Picker("Sound", selection: soundSelection) {
                            Text(SoundChoice.wallflowerPing.settingsTitle).tag(SoundChoice.wallflowerPing)
                            Divider()
                            ForEach(model.systemSounds, id: \.self) { name in
                                Text(name).tag(SoundChoice.system(name))
                            }
                            if let name = model.customSoundName {
                                Divider()
                                Text(name).tag(SoundChoice.custom)
                            }
                            Divider()
                            Text(SoundChoice.none.settingsTitle).tag(SoundChoice.none)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        // Neutral, like the segmented controls: the mint accent is for switches and the active page.
                        .tint(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            model.previewSound()
                        } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                        .buttonStyle(WelcomePillButtonStyle())
                        .disabled(isSilent)
                    }
                }
                WelcomeHairline()
                WelcomeChoiceRow(title: "Volume") {
                    Slider(value: $model.sound.volume, in: 0...1) { editing in
                        // Let go: hear the new level once.
                        if !editing { model.previewSound() }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Volume")
                }
                .disabled(isSilent)
                WelcomeHairline()
                moment("When it's your turn", status: .yourTurn(since: model.idleSince), seed: "welcome-sound-turn", isOn: $model.sound.onDone)
                WelcomeHairline()
                moment("When it needs you", status: .needsInput(kind: .question), seed: "welcome-sound-needs", isOn: $model.sound.onNeedsInput)
            }
            .welcomeCard()
            .padding(.top, 26)
            Text("Use your own sound file in Settings > Sound.")
                .font(.system(size: 12))
                .foregroundStyle(WelcomeStyle.tertiary)
                .padding(.top, 14)
        }
    }

    /// The picker shows what plays and plays a new pick once.
    private var soundSelection: Binding<SoundChoice> {
        Binding(get: { model.shownSound }, set: { model.pickSound($0) })
    }

    /// One moment the sound plays for: its face, a sentence, a switch.
    private func moment(_ title: String, status: FaceStatus, seed: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            StatusFace(look: look, status: status, seed: seed, size: 22)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .frame(width: WelcomeStyle.setUpContentWidth)
        .padding(.horizontal, WelcomeStyle.setUpInset)
        .padding(.vertical, 10)
        .disabled(isSilent)
    }
}

/// A small soft capsule with a symbol and a word: "Preview".
struct WelcomePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WelcomePillLabel(configuration: configuration)
    }

    private struct WelcomePillLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.1), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}
