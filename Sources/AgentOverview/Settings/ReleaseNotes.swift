import Foundation

/// One version's section of `CHANGELOG.md` (Keep a Changelog: `## [1.5] - 2026-10-27`, then
/// `### Added`, `### Changed`, `### Fixed` ... with `- ` bullets). `scripts/bundle.sh` copies the
/// changelog into `Contents/Resources`, and Settings > What's New shows it (`WhatsNewContent`).
/// Bullet text stays Markdown; `inline(_:)` renders it.
struct ReleaseNotes: Equatable, Identifiable, Sendable {
    /// "1.5", "0.1.3", or "Unreleased".
    var version: String
    /// "2026-10-27" as written, nil for [Unreleased].
    var date: String?
    /// Paragraphs between the heading and the first group ("The first public release.").
    var intro: [String] = []
    /// The groups in display order (`ChangeKind.order`), one per kind.
    var groups: [ChangeGroup] = []

    var id: String { version }

    /// The section's name for the release being worked on; publish.sh renames it on release.
    static let unreleased = "Unreleased"

    var isUnreleased: Bool { version == Self.unreleased }

    /// Whether there is anything to show.
    var isEmpty: Bool { intro.isEmpty && groups.allSatisfy(\.items.isEmpty) }

    /// The release date as a `Date` (midnight UTC), nil without one or for an unreadable one.
    var releaseDate: Date? {
        date.flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle().year().month().day()) }
    }
}

/// The bullets of one `###` group.
struct ChangeGroup: Equatable, Identifiable, Sendable {
    var kind: ChangeKind
    var items: [String]

    var id: ChangeKind { kind }
}

/// What a group's heading says, in the words Settings uses: Added is New, Changed is Improved.
enum ChangeKind: Hashable, Sendable {
    case new, improved, fixed, removed
    /// Any other heading (Security, Deprecated), shown under its own name.
    case other(String)

    init(heading: String) {
        switch heading.trimmingCharacters(in: .whitespaces).lowercased() {
        case "added": self = .new
        case "changed": self = .improved
        case "fixed": self = .fixed
        case "removed": self = .removed
        default: self = .other(heading.trimmingCharacters(in: .whitespaces))
        }
    }

    var title: String {
        switch self {
        case .new: "New"
        case .improved: "Improved"
        case .fixed: "Fixed"
        case .removed: "Removed"
        case .other(let heading): heading
        }
    }

    /// SF Symbol next to the title.
    var symbolName: String {
        switch self {
        case .new: "sparkles"
        case .improved: "arrow.up.circle"
        case .fixed: "checkmark.circle"
        case .removed: "minus.circle"
        case .other: "info.circle"
        }
    }

    /// New first, then Improved, Fixed, Removed, then anything else in the file's order.
    var order: Int {
        switch self {
        case .new: 0
        case .improved: 1
        case .fixed: 2
        case .removed: 3
        case .other: 4
        }
    }
}

extension ReleaseNotes {
    /// Every `## [...]` section of a Keep a Changelog file, in the file's order (newest first).
    /// Continuation lines join their bullet; link references (`[1.5]: https://...`) and publish.sh's
    /// "Will be released as" line are left out, as `scripts/appcast.sh` leaves them out.
    static func parse(_ markdown: String) -> [ReleaseNotes] {
        var releases: [ReleaseNotes] = []
        var release: ReleaseNotes?
        // Groups in the file's order until the section ends; sorted and merged then.
        var groups: [ChangeGroup] = []
        var item: String?
        var paragraph: String?

        func endBlock() {
            // Before any group a bullet or paragraph is the intro; inside one, one more entry of that group.
            for text in [item, paragraph].compactMap(\.self) {
                if groups.isEmpty { release?.intro.append(text) } else { groups[groups.count - 1].items.append(text) }
            }
            item = nil
            paragraph = nil
        }
        func endRelease() {
            endBlock()
            guard var finished = release else { return }
            finished.groups = merged(groups)
            releases.append(finished)
            release = nil
            groups = []
        }

        // `isNewline`: "\r\n" is one Character in Swift, so splitting on "\n" would miss it.
        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("## ") {
                endRelease()
                release = heading(line)
                continue
            }
            guard release != nil else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                endBlock()
            } else if line.hasPrefix("### ") {
                endBlock()
                groups.append(ChangeGroup(kind: ChangeKind(heading: String(line.dropFirst(4))), items: []))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                endBlock()
                item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if isLinkReference(trimmed) || trimmed.hasPrefix("Will be released as ") {
                endBlock()
            } else if let text = item {
                item = text + " " + trimmed
            } else {
                paragraph = paragraph.map { $0 + " " + trimmed } ?? trimmed
            }
        }
        endRelease()
        return releases
    }

    /// `## [1.5] - 2026-10-27` or `## [Unreleased]`; nil for a `##` heading of another shape.
    private static func heading(_ line: String) -> ReleaseNotes? {
        guard let match = line.wholeMatch(of: /## \[([^\]]+)\](?:\s+-\s+(\S+))?\s*/) else { return nil }
        return ReleaseNotes(version: String(match.1), date: match.2.map(String.init))
    }

    /// `[1.5]: https://...` at the bottom of the file.
    private static func isLinkReference(_ line: String) -> Bool {
        line.wholeMatch(of: /\[[^\]]+\]:\s+\S+.*/) != nil
    }

    /// One group per kind (a repeated heading adds to the first), empty ones dropped, in `ChangeKind.order`.
    private static func merged(_ groups: [ChangeGroup]) -> [ChangeGroup] {
        var result: [ChangeGroup] = []
        for group in groups where !group.items.isEmpty {
            if let index = result.firstIndex(where: { $0.kind == group.kind }) {
                result[index].items += group.items
            } else {
                result.append(group)
            }
        }
        // Stable: equal orders keep the file's order.
        return result.enumerated()
            .sorted { ($0.element.kind.order, $0.offset) < ($1.element.kind.order, $1.offset) }
            .map(\.element)
    }

    /// A bullet's Markdown as styled text: `**bold**`, `*italic*` and `` `code` `` as such, no
    /// asterisks or backticks left. Web links stay links; a link into the repository
    /// (`docs/agents.md`) leads nowhere from the app, so only its text stays.
    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible
        )
        var text = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        let local = text.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link else { return nil }
            return ["http", "https"].contains(link.scheme?.lowercased() ?? "") ? nil : run.range
        }
        for range in local { text[range].link = nil }
        return text
    }

    /// The changelog `scripts/bundle.sh` copies into `Contents/Resources`, parsed once. A debug build
    /// outside a bundle (`swift run`) reads the checkout's; a release build without one has none.
    static let bundled: [ReleaseNotes] = {
        guard let url = bundledURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()

    private static var bundledURL: URL? {
        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") { return url }
        #if DEBUG
        let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = checkout.appending(path: "CHANGELOG.md")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        #endif
        return nil
    }
}

/// A dotted version ("1.5", "0.1.3"), compared part by part as numbers with missing parts as 0, as
/// `version_gt` in `scripts/publish.sh` does: 1.4 > 0.1.3, 1.10 > 1.9, 1.0 == 1.0.0.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    /// nil for anything but digits and dots ("dev", "Unreleased", "1.x", "").
    init?(_ text: String) {
        let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count else { return nil }
        parts = numbers
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}
