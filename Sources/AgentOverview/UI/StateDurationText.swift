import SwiftUI

/// `Needs input · 2m` style text. While `ticking` it updates once a minute (`MinuteSchedule`),
/// the one periodic thing in the app; a row that is not shown gets no entries and never wakes.
/// The view type is the same either way, so turning ticking on or off swaps nothing.
/// An external session's `tool` leads (`codex · Working · 2m`) and is what gets truncated when the
/// line is too long, so the status and the time always show.
struct StateDurationText: View {
    let label: String
    let since: Date
    var ticking = true
    var tool: String?

    var body: some View {
        TimelineView(MinuteSchedule(since: since, ticking: ticking)) { context in
            HStack(spacing: 0) {
                if let tool {
                    Text("\(tool) · ")
                        .truncationMode(.tail)
                }
                Text(Self.text(label: label, since: since, now: context.date))
                    .layoutPriority(1)
            }
        }
    }

    /// The whole line as one string: `codex · Working · 2m`, or `Working · Coding · 2m` without a tool.
    static func text(tool: String?, label: String, since: Date, now: Date) -> String {
        let text = Self.text(label: label, since: since, now: now)
        guard let tool else { return text }
        return "\(tool) · \(text)"
    }

    /// `<label> · <duration>`.
    static func text(label: String, since: Date, now: Date) -> String {
        "\(label) · \(duration(since: since, now: now))"
    }

    /// Under a minute `now`, then `Nm`, from an hour `Hh Mm`, from a day `Dd`.
    static func duration(since: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(since), 0)
        let minutes = Int(seconds / 60)
        switch minutes {
        case ..<1: return "now"
        case ..<60: return "\(minutes)m"
        case ..<(24 * 60): return "\(minutes / 60)h \(minutes % 60)m"
        default: return "\(minutes / (24 * 60))d"
        }
    }
}
