import Foundation

/// One entry of `actions.json`: a face below the divider that starts a Claude Code session running
/// `prompt` in `cwd`. Only `id`, `name`, `cwd` and `prompt` are required; `seed` picks the face
/// identity (defaults to the id), `symbol` is an SF Symbol name for later use, `shape` a `BlobShape`
/// raw value and `color` a `#RRGGBB` hex, both overriding the `Theme` action look for this item.
/// `days` limits the face to some weekdays (`ActionSchedule`); without it the face shows every day.
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

    init(
        id: String, name: String, cwd: String, prompt: String, seed: String? = nil, symbol: String? = nil, shape: String? = nil,
        color: String? = nil, days: [String]? = nil
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
