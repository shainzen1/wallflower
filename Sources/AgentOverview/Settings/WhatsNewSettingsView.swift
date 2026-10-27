import AppKit
import Observation
import SwiftUI

/// The What's New tab: the running version up top (icon, "What's New in 1.5", the release date and
/// a count per group), its changes as one card per group (New, Improved, Fixed, ...), then the
/// earlier versions, each behind a disclosure. The notes are the bundled `CHANGELOG.md`
/// (`ReleaseNotes.bundled`). Opens by itself once after an update (`WhatsNewLaunch`).
struct WhatsNewSettingsView: View {
    let content: WhatsNewContent
    @Bindable var state: WhatsNewViewState

    var body: some View {
        Form {
            Section {
                header
            }

            if let current = content.current {
                ForEach(current.groups) { group in
                    Section {
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            ChangeText(markdown: item)
                                .padding(.vertical, 2)
                        }
                    } header: {
                        ChangeGroupLabel(kind: group.kind)
                    }
                }
            }

            if !content.earlier.isEmpty {
                Section {
                    ForEach(content.earlier) { release in
                        DisclosureGroup(isExpanded: state.isExpanded(release.version)) {
                            EarlierReleaseView(release: release)
                        } label: {
                            LabeledContent {
                                Text(Self.dateText(release))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Text("Version \(release.version)")
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Earlier versions")
                } footer: {
                    if let url = AppInfo.repositoryURL {
                        Button("All releases on GitHub") { NSWorkspace.shared.open(url.appending(path: "releases")) }
                            .buttonStyle(.link)
                            .pointerStyle(.link)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// Icon, title, date or the empty note, and the counts.
    private var header: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            Text(content.current == nil ? "What's New" : "What's New in \(content.version)")
                .font(.title2.weight(.semibold))
                .padding(.top, 6)
            Text(Self.subtitle(content))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if let current = content.current {
                ForEach(Array(current.intro.enumerated()), id: \.offset) { _, paragraph in
                    ChangeText(markdown: paragraph)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                if !current.groups.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(current.groups) { group in
                            ChangeCountBadge(kind: group.kind, count: group.items.count)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// "Released 27 October 2026", "Not released yet", or why there is nothing to show.
    static func subtitle(_ content: WhatsNewContent) -> String {
        guard let current = content.current else {
            return AppVersion(content.version) == nil
                ? "Release notes come with the app."
                : "No release notes for version \(content.version)."
        }
        guard let date = current.releaseDate else { return "Version \(content.version), not released yet" }
        return "Released \(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))"
    }

    /// An earlier version's date, short ("23 Oct 2026"), or empty.
    static func dateText(_ release: ReleaseNotes) -> String {
        release.releaseDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) ?? ""
    }
}

/// Which earlier versions are open. `--settings-advanced` opens the newest one (for snapshots).
@Observable @MainActor
final class WhatsNewViewState {
    var expanded: Set<String>

    init(expanded: Set<String> = []) {
        self.expanded = expanded
    }

    func isExpanded(_ version: String) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(version) },
            set: { open in
                if open { self.expanded.insert(version) } else { self.expanded.remove(version) }
            }
        )
    }
}

/// A group's colour: one hue per kind, so New, Improved and Fixed read apart at a glance.
extension ChangeKind {
    var tint: Color {
        switch self {
        case .new: .blue
        case .improved: .purple
        case .fixed: .green
        case .removed: .orange
        case .other: .secondary
        }
    }
}

/// The group's symbol in its colour, then its name: a section header.
private struct ChangeGroupLabel: View {
    let kind: ChangeKind

    var body: some View {
        Label {
            Text(kind.title)
        } icon: {
            Image(systemName: kind.symbolName)
                .foregroundStyle(kind.tint)
        }
    }
}

/// The group's symbol and "2 New" in its colour, on a light tint of it.
private struct ChangeCountBadge: View {
    let kind: ChangeKind
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbolName)
                .imageScale(.small)
            Text("\(count) \(kind.title)")
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(kind.tint)
        .background(kind.tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// One change: its Markdown rendered (bold, code, web links), wrapping.
private struct ChangeText: View {
    let markdown: String

    var body: some View {
        Text(ReleaseNotes.inline(markdown))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// An earlier version, opened: its intro, then each group's name and its changes as a bulleted list.
private struct EarlierReleaseView: View {
    let release: ReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(release.intro.enumerated()), id: \.offset) { _, paragraph in
                ChangeText(markdown: paragraph)
                    .foregroundStyle(.secondary)
            }
            ForEach(release.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    ChangeGroupLabel(kind: group.kind)
                        .font(.callout.weight(.semibold))
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(.tertiary)
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                                .accessibilityHidden(true)
                            ChangeText(markdown: item)
                        }
                    }
                }
            }
        }
        .font(.callout)
        .padding(.vertical, 6)
    }
}
