import Foundation
import Testing
@testable import AgentOverview

/// A clock the tests move by hand (a class so the store's closure sees the changes).
@MainActor
private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

/// Zurich, Gregorian: the calendar of the schedule tests (DST ends on October 25, 2026).
private let zurich: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return calendar
}()

/// A local date and time in Zurich.
private func local(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, month: Int = 10) -> Date {
    zurich.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private extension ActionItem {
    static let weekly = ActionItem(id: "weekly", name: "Weekly", cwd: "~/notes", prompt: "/weekly", days: ["thu", "fri"])
}

@Suite("Action schedule")
struct ActionScheduleTests {
    @Test("Weekday keys: every day of a week in October 2026, Monday first, in the calendar's time zone")
    func weekdayKeys() {
        #expect(ActionSchedule.weekdayKeys == ["mon", "tue", "wed", "thu", "fri", "sat", "sun"])
        #expect(ActionSchedule.weekdayLetters.count == 7 && ActionSchedule.weekdayNames.count == 7)
        // October 12, 2026 is a Monday.
        for (offset, key) in ActionSchedule.weekdayKeys.enumerated() {
            #expect(ActionSchedule.weekdayKey(for: local(12 + offset), calendar: zurich) == key)
            #expect(ActionSchedule.weekdayKey(for: local(12 + offset, 0, 0), calendar: zurich) == key, "local midnight")
            #expect(ActionSchedule.weekdayKey(for: local(12 + offset, 23, 59), calendar: zurich) == key)
        }
        // Friday 00:30 in Zurich is still Thursday in UTC: the local day counts.
        #expect(ActionSchedule.weekdayKey(for: local(16, 0, 30), calendar: zurich) == "fri")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(ActionSchedule.weekdayKey(for: local(16, 0, 30), calendar: utc) == "thu")
    }

    @Test("Shown days: nil, empty and unknown-only mean every day; unknown keys are ignored")
    func shownDays() {
        for day in 12...18 {
            let date = local(day)
            #expect(ActionSchedule.isShown(days: nil, on: date, calendar: zurich))
            #expect(ActionSchedule.isShown(days: [], on: date, calendar: zurich))
            #expect(ActionSchedule.isShown(days: ["xyz", "Thursday"], on: date, calendar: zurich), "no known key: every day")
            #expect(ActionSchedule.isShown(days: ActionSchedule.weekdayKeys, on: date, calendar: zurich))
        }
        let thuFri = ["thu", "fri"]
        let shown = (12...18).filter { ActionSchedule.isShown(days: thuFri, on: local($0), calendar: zurich) }
        #expect(shown == [15, 16])
        let withUnknown = (12...18).filter { ActionSchedule.isShown(days: ["sun", "nope", "THU"], on: local($0), calendar: zurich) }
        #expect(withUnknown == [15, 18], "keys match in any case, unknown ones are ignored")
        #expect(ActionSchedule.knownDays(["fri", "mon", "fri", "x"]) == ["mon", "fri"])
        #expect(ActionItem.weekly.isShown(on: local(15), calendar: zurich) && !ActionItem.weekly.isShown(on: local(14), calendar: zurich))
    }

    @Test("Next day change: the next local midnight, strictly after; 25 hours across the end of DST")
    func nextDayChange() {
        #expect(ActionSchedule.nextDayChange(after: local(15, 12), calendar: zurich) == local(16, 0))
        #expect(ActionSchedule.nextDayChange(after: local(15, 0), calendar: zurich) == local(16, 0), "at midnight: the next one")
        #expect(ActionSchedule.nextDayChange(after: local(15, 23, 59), calendar: zurich) == local(16, 0))
        #expect(ActionSchedule.nextDayChange(after: local(31, 18), calendar: zurich) == local(1, 0, month: 11), "into November")

        // October 25, 2026: 03:00 CEST becomes 02:00 CET in Zurich.
        let saturdayNoon = local(24, 12)
        let sundayMidnight = ActionSchedule.nextDayChange(after: saturdayNoon, calendar: zurich)
        #expect(sundayMidnight == local(25, 0))
        #expect(sundayMidnight == Date(timeIntervalSince1970: 1_792_879_200), "October 24, 22:00 UTC (CEST)")
        let mondayMidnight = ActionSchedule.nextDayChange(after: sundayMidnight, calendar: zurich)
        #expect(mondayMidnight == local(26, 0))
        #expect(mondayMidnight.timeIntervalSince(sundayMidnight) == 25 * 3600, "the long day")
        #expect(ActionSchedule.nextDayChange(after: local(25, 2, 30), calendar: zurich) == mondayMidnight)
        #expect(ActionSchedule.weekdayKey(for: mondayMidnight, calendar: zurich) == "mon")
    }

    @Test("Toggling: all on is stored as nil, the last day stays on, unknown keys drop out; captions")
    func toggling() {
        #expect(ActionSchedule.enabledDays(nil) == Set(ActionSchedule.weekdayKeys))
        #expect(ActionSchedule.enabledDays(["x"]) == Set(ActionSchedule.weekdayKeys))
        #expect(ActionSchedule.toggling("mon", in: nil) == ["tue", "wed", "thu", "fri", "sat", "sun"])
        #expect(ActionSchedule.toggling("mon", in: ["tue", "wed", "thu", "fri", "sat", "sun"]) == nil, "all seven on: omitted")
        #expect(ActionSchedule.toggling("fri", in: ["thu", "fri"]) == ["thu"])
        #expect(ActionSchedule.toggling("thu", in: ["thu"]) == ["thu"], "the last day cannot be turned off")
        #expect(ActionSchedule.toggling("mon", in: ["fri", "thu", "x"]) == ["mon", "thu", "fri"], "Monday-first order, unknown dropped")
        #expect(ActionSchedule.toggling("nope", in: ["thu"]) == ["thu"])
        #expect(ActionSchedule.storedDays([]) == nil && ActionSchedule.storedDays(Set(ActionSchedule.weekdayKeys)) == nil)
        #expect(ActionSchedule.caption(nil) == "Every day" && ActionSchedule.caption(ActionSchedule.weekdayKeys) == "Every day")
        #expect(ActionSchedule.caption(["fri", "thu"]) == "Thu, Fri")
    }

    @Test("File format: days round-trip and are omitted when nil, keys stay sorted")
    func roundTrip() throws {
        let items = [ActionItem.standup, ActionItem.weekly]
        let data = try ActionItem.encode(items)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.components(separatedBy: "\"days\"").count == 2, "only the scheduled item carries days")
        #expect(text.contains("\"cwd\" : \"~/notes\",\n    \"days\" : [\n      \"thu\",\n      \"fri\"\n    ],\n    \"id\""), "sorted keys")
        #expect(try ActionItem.decode(data) == items)
        let decoded = try ActionItem.decode(Data(#"[{"id": "a", "name": "A", "cwd": "/tmp", "prompt": "p", "days": ["sat", "zzz"]}]"#.utf8))
        #expect(decoded[0].days == ["sat", "zzz"], "unknown keys are kept in the file, only ignored")
        #expect(throws: (any Error).self) { try ActionItem.decode(Data(#"[{"id": "a", "name": "A", "cwd": "/tmp", "prompt": "p", "days": "thu"}]"#.utf8)) }
    }
}

@Suite("Action store schedule")
@MainActor
struct ActionStoreScheduleTests {
    private func makeStore(_ items: [ActionItem], clock: TestClock) throws -> (URL, ActionStore) {
        let folder = try TestSupport.makeTempFolder()
        let file = folder.appending(path: "actions.json")
        try ActionItem.encode(items).write(to: file)
        let store = ActionStore(fileURL: file, calendar: zurich, now: { clock.date })
        return (folder, store)
    }

    @Test("Visible actions: today's items in file order, all items kept; the day moves on with the clock")
    func filtering() throws {
        let clock = TestClock(local(14, 9))  // Wednesday
        let daily = ActionItem(id: "daily", name: "Daily", cwd: "~/notes", prompt: "/daily")
        let weekend = ActionItem(id: "weekend", name: "Weekend", cwd: "~/notes", prompt: "/weekend", days: ["sat", "sun"])
        let (folder, store) = try makeStore([.weekly, daily, weekend], clock: clock)
        defer { store.stop(); try? FileManager.default.removeItem(at: folder) }
        store.start()
        #expect(store.actions.map(\.id) == ["weekly", "daily", "weekend"])
        #expect(store.today == local(14, 0))
        #expect(store.visibleActions.map(\.id) == ["daily"])
        #expect(store.visibleActions(on: local(16)).map(\.id) == ["weekly", "daily"], "file order")
        #expect(store.visibleActions(on: local(18)).map(\.id) == ["daily", "weekend"])

        let model = PanelModel(store: SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil), actionStore: store)
        #expect(model.actionRows.map(\.id) == ["daily"] && model.slotCount == 1)

        clock.date = local(14, 23, 59)
        store.refreshDay()
        #expect(store.today == local(14, 0), "same day: nothing moves")
        clock.date = local(15, 0, 0, month: 10)  // Thursday midnight
        store.refreshDay()
        #expect(store.today == local(15, 0))
        #expect(store.visibleActions.map(\.id) == ["weekly", "daily"])
        #expect(model.actionRows.map(\.id) == ["weekly", "daily"], "the panel's rows follow the day")
        #expect(store.actions.count == 3)
    }

    @Test("Save: writes the file atomically, takes the list over at once, the watcher's reload changes nothing")
    func save() async throws {
        let clock = TestClock(local(15))
        let (folder, store) = try makeStore([.standup], clock: clock)
        defer { store.stop(); try? FileManager.default.removeItem(at: folder) }
        store.start()
        #expect(store.actions == [.standup])

        var edited = [ActionItem.standup, ActionItem.weekly]
        edited[0].days = ["mon"]
        try store.save(edited)
        #expect(store.actions == edited, "no wait for the watcher")
        #expect(try ActionItem.decode(Data(contentsOf: store.fileURL)) == edited)
        #expect(store.visibleActions.map(\.id) == ["weekly"])

        edited[0].days = nil
        try store.save(edited)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.components(separatedBy: "\"days\"").count == 2, "nil days are omitted")
        #expect(text.hasSuffix("]\n"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.actions == edited && store.lastError == nil, "the reload found the same list")
    }
}
