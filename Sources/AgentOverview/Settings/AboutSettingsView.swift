import AppKit
import SwiftUI

/// The About tab, a small credits card: icon, name, version and tagline, the "Made by" line (the
/// author links to GitHub, the studio to its site), then the buttons: "View on GitHub" (only once
/// `AppInfo.repositoryURL` exists), the coffee button and "Show welcome again". The licence line
/// sits below the card.
///
/// The coffee button needs `AppInfo.sponsorURL`, which `scripts/publish.sh --bmc` fills in the export.
/// While it is nil, a debug build still shows the button, disabled with a tooltip, so the layout can be
/// judged; a release build (published without a donation page) leaves it out.
struct AboutSettingsView: View {
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text(AppInfo.name)
                        .font(.title2.weight(.semibold))
                        .padding(.top, 10)
                    Text("Version \(AppInfo.version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .padding(.top, 2)
                    Text(AppInfo.tagline)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                        .padding(.top, 12)
                    credits
                        .padding(.top, 14)
                    buttons
                        .padding(.top, 18)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } footer: {
                Text("MIT License. Not affiliated with Anthropic.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    /// "Made by Shain Gerstner · osoro.studio", the two names as links.
    private var credits: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Made by")
                .foregroundStyle(.secondary)
            CreditLink(title: AppInfo.authorName, url: AppInfo.authorGitHubURL)
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            CreditLink(title: AppInfo.studioName, url: AppInfo.studioURL)
        }
        .font(.callout)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let url = AppInfo.repositoryURL {
                Button("View on GitHub") { NSWorkspace.shared.open(url) }
            }
            if Self.showsSponsorButton(url: AppInfo.sponsorURL, placeholder: Self.showsSponsorPlaceholder) {
                coffeeButton
            }
            Button("Show welcome again", action: actions.showWelcome)
        }
    }

    /// Prominent and in the accent colour. Disabled without a donation page; the tooltip sits on a
    /// wrapper, so it shows on the disabled button too.
    private var coffeeButton: some View {
        let url = AppInfo.sponsorURL
        return Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            Label(Self.sponsorTitle(for: url), systemImage: Self.sponsorSymbol(for: url))
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(url == nil)
        .padding(1)
        .contentShape(.rect)
        .help(Self.sponsorHelp(for: url))
    }

    /// Whether a build without a donation page shows the coffee button disabled: debug builds only.
    #if DEBUG
    nonisolated static let showsSponsorPlaceholder = true
    #else
    nonisolated static let showsSponsorPlaceholder = false
    #endif

    /// The coffee button shows with a donation page, or disabled as a placeholder without one.
    nonisolated static func showsSponsorButton(url: URL?, placeholder: Bool) -> Bool {
        url != nil || placeholder
    }

    /// The donate button's title, after the donation page's host.
    nonisolated static func sponsorTitle(for url: URL) -> String {
        var host = url.host()?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return switch host {
        case "buymeacoffee.com": "Buy me a coffee"
        case "github.com": "Sponsor on GitHub"
        case "ko-fi.com": "Support on Ko-fi"
        default: "Support \(AppInfo.name)"
        }
    }

    /// The title before the page exists: release builds get a Buy Me a Coffee page (`--bmc`).
    nonisolated static func sponsorTitle(for url: URL?) -> String {
        url.map { sponsorTitle(for: $0) } ?? "Buy me a coffee"
    }

    /// The button's SF Symbol: a cup for the coffee pages (and before the page exists), a heart otherwise.
    nonisolated static func sponsorSymbol(for url: URL?) -> String {
        switch url.map({ sponsorTitle(for: $0) }) {
        case nil, "Buy me a coffee", "Support on Ko-fi": "cup.and.saucer.fill"
        default: "heart.fill"
        }
    }

    /// The tooltip: where the button goes, or why it is disabled.
    nonisolated static func sponsorHelp(for url: URL?) -> String {
        guard let url else { return "Set in release builds" }
        return linkHelp(for: url)
    }

    /// A link's tooltip: the address without the scheme and a trailing slash ("github.com/demo").
    nonisolated static func linkHelp(for url: URL) -> String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

/// A name in the credits line: link coloured, the pointing hand on hover, opens in the default browser.
private struct CreditLink: View {
    let title: String
    let url: URL

    var body: some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.link)
            .pointerStyle(.link)
            .help(AboutSettingsView.linkHelp(for: url))
            .accessibilityHint("Opens \(AboutSettingsView.linkHelp(for: url)) in your browser")
    }
}
