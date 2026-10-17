import Observation
import SwiftUI

/// The Appearance tab: a live preview of four faces in the current look, the face settings, and
/// the rarely touched ones behind an Advanced disclosure. Every change applies to the panel at once.
struct AppearanceSettingsView: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions
    /// The Advanced disclosure (the toolchain has no `@State`, so view state lives in a model).
    @Bindable var state: AppearanceViewState

    var body: some View {
        VStack(spacing: 0) {
            AppearancePreview(look: settings.look, idleSince: state.idleSince)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Face", selection: $settings.faceStyle) {
                    ForEach(FaceStyle.settingsOrder, id: \.self) { Text($0.settingsTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Screen filter", selection: $settings.faceFilter) {
                    ForEach(FaceFilter.allCases, id: \.self) { Text($0.settingsTitle).tag($0) }
                }
                Picker("Colour", selection: $settings.colorMode) {
                    ForEach(Theme.ColorMode.settingsOrder, id: \.self) { Text($0.settingsTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Shape", selection: $settings.blobShapeMode) {
                    ForEach(Theme.BlobShapeMode.storedChoices, id: \.self) { Text($0.settingsTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(settings.faceStyle != .blob)
                Picker("Hover", selection: $settings.hoverEffect) {
                    ForEach(Theme.HoverEffect.allCases, id: \.self) { Text($0.settingsTitle).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                AdvancedHeader(isExpanded: $state.showsAdvanced)
                if state.showsAdvanced {
                    Picker("Goo", selection: $settings.gooRenderer) {
                        ForEach(Theme.GooRenderer.settingsChoices, id: \.self) { Text($0.settingsTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Expand", selection: $settings.expandMode) {
                        ForEach(Theme.ExpandMode.storedChoices, id: \.self) { Text($0.settingsTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Playground") {
                        Button("Open face playground…", action: actions.openPlayground)
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore defaults") { settings.restoreAppearanceDefaults() }
                        .disabled(settings.isAppearanceDefault)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

/// The Advanced row: a chevron and the title, the whole row a button that shows or hides the rows
/// below it in the same section (a `DisclosureGroup` packs its rows without the form's separators).
struct AdvancedHeader: View {
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                Text("Advanced")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advanced")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// View state of the Appearance tab.
@Observable @MainActor
final class AppearanceViewState {
    var showsAdvanced: Bool
    /// The preview's idle face fell idle when the window opened.
    let idleSince = Date()

    init(showsAdvanced: Bool = false) {
        self.showsAdvanced = showsAdvanced
    }
}

/// The preview strip: a black rounded panel, like the capsule, with the four status faces in the
/// current look. It sits above the form at the width of its sections, with their corner radius.
struct AppearancePreview: View {
    var look: PanelLook
    var idleSince: Date

    /// The grouped form's section corner radius, so the strip reads as one of its surfaces.
    static let cornerRadius: CGFloat = 12

    var body: some View {
        StatusFaceSamples(
            look: look, idleSince: idleSince, faceSize: Theme.faceSize, spacing: 40,
            labelFont: .system(size: 11, weight: .medium), labelColor: .white.opacity(0.6), labelGap: 10
        )
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: needs you, working, idle, done")
    }
}
