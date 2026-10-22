import Foundation

/// One entry of `actions.json`: a face below the divider that starts a Claude Code session running
/// `prompt` in `cwd`. Only `id`, `name`, `cwd` and `prompt` are required; `seed` picks the face
/// identity (defaults to the id), `symbol` is an SF Symbol name for later use, `shape` a `BlobShape`
/// raw value and `color` a `#RRGGBB` hex, both overriding the `Theme` action look for this item.
/// `days` limits the face to some weekdays (`ActionSchedule`); without it the face shows every day.
/// `model` and `effort` pick the Claude Code model and effort of the session (`claude --model`,
/// `--effort`); they only reach the terminal route, the Claude app's link has no such parameters.
struct ActionItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    /// Folder the session starts in; a leading `~` is expanded on launch.
    var cwd: String
    var prompt: String
    var seed: String?
    var symbol: String?
    var shape: String?
    var color: String?
    /// Weekday keys (`mon` to `sun`) the face shows on; nil, empty or no known key means every day.
    /// Omitted from the file when nil.
    var days: [String]?
    /// The `claude --model` value: an alias (`sonnet`) or a full model id, passed on as is after
    /// trimming. Nil or blank means the CLI's own default. Omitted from the file when nil.
    var model: String?
    /// The `claude --effort` level (`ClaudeEffort`). Nil means the CLI's own default; an unknown value
    /// is kept in the file but ignored at launch. Omitted from the file when nil.
    var effort: String?

    init(
        id: String, name: String, cwd: String, prompt: String, seed: String? = nil, symbol: String? = nil, shape: String? = nil,
        color: String? = nil, days: [String]? = nil, model: String? = nil, effort: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.prompt = prompt
        self.seed = seed
        self.symbol = symbol
        self.shape = shape
        self.color = color
        self.days = days
        self.model = model
        self.effort = effort
    }

    /// Seed of the face identity.
    var faceSeed: String { seed ?? "action-\(id)" }

    /// `cwd` with `~` expanded.
    var resolvedCwd: String { NSString(string: cwd).expandingTildeInPath }

    /// The silhouette named by `shape`, when it names one.
    var blobShape: BlobShape? { shape.flatMap(BlobShape.init(rawValue:)) }

    /// Whether the face shows on `date` (local weekday in `calendar`).
    func isShown(on date: Date, calendar: Calendar) -> Bool {
        ActionSchedule.isShown(days: days, on: date, calendar: calendar)
    }

    /// `model` trimmed; nil when blank.
    var launchModel: String? {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `effort` as a level the CLI knows; nil when unset, blank or unknown.
    var launchEffort: ClaudeEffort? { ClaudeEffort(parsing: effort) }

    /// The body colour from `color`, when it parses as `#RRGGBB`.
    var bodyColor: EyeColor? { color.flatMap { EyeColor(hex: $0, name: "action \(id)") } }

    // MARK: File format

    /// Decodes a file: a top-level array of items. Items missing a required key fail the whole decode.
    static func decode(_ data: Data) throws -> [ActionItem] {
        try JSONDecoder().decode([ActionItem].self, from: data)
    }

    static func encode(_ items: [ActionItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(items)
    }
}

/// The effort levels of `claude --effort`.
enum ClaudeEffort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh, max

    /// The level `text` names, trimmed and in any case; nil when blank or unknown.
    init?(parsing text: String?) {
        guard let text else { return nil }
        self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
