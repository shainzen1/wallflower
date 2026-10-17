import Foundation

/// The weekdays an action face shows on, as stored in `actions.json` (`days`): three-letter
/// keys in any case, locale independent. No list, an empty list or a list without a known key means
/// every day; unknown keys are ignored. Pure value logic, no clock of its own.
enum ActionSchedule {
    /// The keys in display order, Monday first.
    static let weekdayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// One-letter labels matching `weekdayKeys`, for the Settings toggles.
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    /// Full names matching `weekdayKeys`, for accessibility and help tags.
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// The key of `date`'s weekday in `calendar` (`Calendar.component(.weekday:)` counts 1 = Sunday).
    static func weekdayKey(for date: Date, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sunday ... 7 = Saturday, mapped onto the Monday-first list.
        return weekdayKeys[(weekday + 5) % 7]
    }

    /// The known keys in `days`, deduplicated, in Monday-first order. Empty means every day.
    /// Keys are matched without regard to case, so a hand-typed `Thu` counts.
    static func knownDays(_ days: [String]?) -> [String] {
        guard let days else { return [] }
        let lowered = days.map { $0.lowercased() }
        return weekdayKeys.filter(lowered.contains)
    }

    /// Whether an item with `days` shows on `date`.
    static func isShown(days: [String]?, on date: Date, calendar: Calendar) -> Bool {
        let known = knownDays(days)
        return known.isEmpty || known.contains(weekdayKey(for: date, calendar: calendar))
    }

    /// The next local midnight after `date`, when the shown set can change next.
    static func nextDayChange(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        if let next = calendar.date(byAdding: .day, value: 1, to: start), next > date {
            return next
        }
        // A calendar that cannot add a day (never seen): an hour later is a safe re-check.
        return date.addingTimeInterval(3600)
    }

    /// The days that are on for a stored value: every key when the value means every day.
    static func enabledDays(_ days: [String]?) -> Set<String> {
        let known = knownDays(days)
        return Set(known.isEmpty ? weekdayKeys : known)
    }

    /// The stored value after flipping `key`. The last day that is on stays on, so an item is never
    /// hidden on every day; unknown keys in `days` are dropped.
    static func toggling(_ key: String, in days: [String]?) -> [String]? {
        var enabled = enabledDays(days)
        if enabled.contains(key) {
            guard enabled.count > 1 else { return storedDays(enabled) }
            enabled.remove(key)
        } else if weekdayKeys.contains(key) {
            enabled.insert(key)
        }
        return storedDays(enabled)
    }

    /// A short caption for Settings: "Every day", or the day names (`Thu, Fri`).
    static func caption(_ days: [String]?) -> String {
        let known = knownDays(days)
        guard !known.isEmpty, known.count < weekdayKeys.count else { return "Every day" }
        return known.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: ", ")
    }

    /// The `days` value to store for a set of enabled keys: nil (omitted) when every day is on or
    /// none is, otherwise the keys in Monday-first order.
    static func storedDays(_ enabled: Set<String>) -> [String]? {
        let known = weekdayKeys.filter(enabled.contains)
        return known.isEmpty || known.count == weekdayKeys.count ? nil : known
    }
}
