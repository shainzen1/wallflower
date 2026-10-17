import SwiftUI

/// Seven small button-style toggles, M T W T F S S (Monday first), for one action's `days`. The only
/// day that is on is disabled, so an action is never hidden on every day (`ActionSchedule.toggling`).
struct WeekdayToggles: View {
    let days: [String]?
    let onToggle: (String) -> Void

    var body: some View {
        let enabled = ActionSchedule.enabledDays(days)
        HStack(spacing: 3) {
            ForEach(Array(ActionSchedule.weekdayKeys.enumerated()), id: \.element) { index, key in
                let isOn = enabled.contains(key)
                Toggle(isOn: Binding(get: { isOn }, set: { _ in onToggle(key) })) {
                    Text(ActionSchedule.weekdayLetters[index])
                        .frame(width: 12)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .disabled(isOn && enabled.count == 1)
                .help(ActionSchedule.weekdayNames[index])
                .accessibilityLabel(ActionSchedule.weekdayNames[index])
            }
        }
        .fixedSize()
    }
}
