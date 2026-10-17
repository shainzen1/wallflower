import SwiftUI

/// Timeline schedule for the time-in-state text: one entry per minute from `since` while `ticking`,
/// no entries at all otherwise. One schedule type for both states keeps the `TimelineView` the same
/// view across hover changes (a view swap would bypass the staggered reveal), and a rest row never ticks.
struct MinuteSchedule: TimelineSchedule {
    let since: Date
    let ticking: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard ticking else { return AnyIterator { nil } }
        let interval: TimeInterval = 60
        let elapsed = max(startDate.timeIntervalSince(since), 0)
        var next = since.addingTimeInterval((elapsed / interval).rounded(.down) * interval)
        return AnyIterator {
            let date = next
            next = next.addingTimeInterval(interval)
            return date
        }
    }
}
