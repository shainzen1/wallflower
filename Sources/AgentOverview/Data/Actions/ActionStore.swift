import Foundation
import Observation

/// The action faces, read from `actions.json` (in `AppInfo.supportFolder` by default,
/// `--actions-file <path>` otherwise). The file is created as an empty list on first launch,
/// decoded on the main actor, and reloaded whenever it changes on disk (vnode source, no polling).
/// A file that fails to decode keeps the last good list.
///
/// Items with `days` show only on those weekdays: `visibleActions` is the list for `today`, in file
/// order. `today` moves on at local midnight through one one-shot timer (re-armed after it fires) and
/// on the system's day-change, clock-change and time zone notifications, which cover sleep and wake.
/// Nothing polls.
@Observable @MainActor
final class ActionStore {
    /// Every item of the file, in file order (Settings edits these).
    private(set) var actions: [ActionItem] = []
    /// Start of the local day the visible list is evaluated for.
    private(set) var today: Date
    /// Set when the last read failed to decode (the menu could surface it later).
    private(set) var lastError: String?

    let fileURL: URL
    /// The calendar weekdays and midnights are taken from.
    let calendar: Calendar
    /// The clock (tests inject one).
    private let now: @MainActor () -> Date
    @ObservationIgnored private var watcher: ActionFileWatcher?
    @ObservationIgnored private var dayTimer: Timer?
    @ObservationIgnored private var dayObservers: [NSObjectProtocol] = []

    static var defaultFileURL: URL {
        AppInfo.supportFolder.appending(path: "actions.json", directoryHint: .notDirectory)
    }

    init(
        fileURL: URL = ActionStore.defaultFileURL, calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        today = calendar.startOfDay(for: now())
    }

    /// The items shown today, in file order.
    var visibleActions: [ActionItem] {
        visibleActions(on: today)
    }

    /// The items shown on `date`, in file order.
    func visibleActions(on date: Date) -> [ActionItem] {
        actions.filter { $0.isShown(on: date, calendar: calendar) }
    }

    /// Creates the file when missing, reads it, then watches it and the day. Calling it twice is a no-op.
    func start() {
        guard watcher == nil else { return }
        createDefaultFileIfMissing()
        reload()
        let watcher = ActionFileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        self.watcher = watcher
        watcher.start()
        observeDayChanges()
        refreshDay()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        dayTimer?.invalidate()
        dayTimer = nil
        for observer in dayObservers { NotificationCenter.default.removeObserver(observer) }
        dayObservers = []
    }

    /// Re-reads the clock: moves `today` on when the local day changed (the panel's rows follow) and
    /// re-arms the midnight timer.
    func refreshDay() {
        let date = now()
        if !calendar.isDate(date, inSameDayAs: today) {
            today = calendar.startOfDay(for: date)
        }
        if watcher != nil { armDayTimer(after: date) }
    }

    /// Writes `items` to the file (atomically) and takes them over at once, so Settings does not wait
    /// for the watcher; its reload then finds the same list and changes nothing.
    func save(_ items: [ActionItem]) throws {
        var data = try ActionItem.encode(items)
        data.append(contentsOf: Data("\n".utf8))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        if items != actions { actions = items }
        if lastError != nil { lastError = nil }
    }

    /// Reads the file and replaces `actions` when the list changed.
    func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let items = try ActionItem.decode(data)
            if items != actions { actions = items }
            if lastError != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
            NSLog("%@: actions.json not readable: %@", AppInfo.name, error.localizedDescription)
        }
    }

    // MARK: Private

    /// One one-shot timer for the next local midnight. A timer does not count the time asleep, so a
    /// wake past midnight is caught by `NSCalendarDayChanged` instead.
    private func armDayTimer(after date: Date) {
        dayTimer?.invalidate()
        let timer = Timer(fire: ActionSchedule.nextDayChange(after: date, calendar: calendar), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDay() }
        }
        timer.tolerance = DataTuning.dayChangeTolerance
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }

    private func observeDayChanges() {
        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        dayObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDay() }
            }
        }
    }

    /// A missing file starts as an empty list (`[]`): no action faces until the person adds one.
    private func createDefaultFileIfMissing() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("[]\n".utf8).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("%@: could not create actions.json: %@", AppInfo.name, error.localizedDescription)
        }
    }
}
