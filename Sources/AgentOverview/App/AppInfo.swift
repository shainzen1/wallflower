import Foundation

/// The app's public identity in one place: name, bundle id, folders and links.
/// The SwiftPM target keeps its working name (`AgentOverview`); everything a person sees says `name`.
enum AppInfo {
    static let name = "Wallflower"
    static let tagline = "Your Claude Code sessions, waiting quietly at the edge of your screen."
    /// Matches `CFBundleIdentifier` in `Packaging/Info.plist`. Also the log subsystem and the queue label prefix.
    static let bundleIdentifier = "dev.wallflower.Wallflower"

    /// `CFBundleShortVersionString`, or "dev" when running outside a bundle (`swift run`, tests).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// `~/Library/Application Support/Wallflower/`: `actions.json` and anything else the app writes.
    static var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/\(name)", directoryHint: .isDirectory)
    }

    /// Who made it, shown in Settings > About and the README's credits. Fixed in the source, unlike
    /// the links below: none of them is a placeholder.
    static let authorName = "Shain Gerstner"
    static let authorGitHubURL = URL(string: "https://github.com/shainzen1")!
    static let studioName = "osoro.studio"
    static let studioURL = URL(string: "https://osoro.studio")!

    /// The public repository. nil until it exists; every link to it hides while nil.
    static let repositoryURL: URL? = URL(string: "https://github.com/shainzen1/wallflower")
    /// The donation page (Buy Me a Coffee, GitHub Sponsors, Ko-fi). nil in the source: `scripts/publish.sh`
    /// fills it in the export (`--bmc <handle>`). While nil, the About tab's coffee button shows disabled in a
    /// debug build and is left out of a release build.
    static let sponsorURL: URL? = URL(string: "https://buymeacoffee.com/shainzen1")
}
