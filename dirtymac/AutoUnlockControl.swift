import SwiftUI

/// What the auto-unlock timer is set to, apart from where it is stored: a length picked from
/// the list, a length entered by hand ("For 3 hr 15 min") or a time of day ("Until 23:30").
/// The rules of the control live here, so they can be tested without drawing it.
nonisolated struct AutoUnlockEntry: Equatable {
    var seconds: Int
    /// Minutes after midnight, nil when the timer is a length.
    var atMinutes: Int?
    var custom: Bool

    /// The picker entry that opens the box for a hand-entered value. A picked length is its
    /// own seconds, which are never negative.
    static let customTag = -2

    /// The shortest and longest hand-entered length.
    static let minCustomSeconds = 60
    static let maxCustomSeconds = LockConfiguration.maxAutoUnlockSeconds

    var isClock: Bool { atMinutes != nil }

    /// What the picker shows. A frozen mouse has no "Off" and no length under 30 seconds, so what
    /// the lock will use is what is shown.
    func selection(mouseFrozen: Bool) -> Int {
        let used = mouseFrozen ? LockConfiguration.clampedSeconds(seconds, mouseLocked: true) : seconds
        if custom || isClock || !LockConfiguration.unlockChoices.contains(used) { return Self.customTag }
        return used
    }

    /// The entry after the picker was moved to `tag`.
    func choosing(_ tag: Int) -> AutoUnlockEntry {
        if tag == Self.customTag {
            var entry = self
            entry.custom = true
            // Starts from the length that was on offer, an hour if there was none.
            if !isClock, seconds < Self.minCustomSeconds { entry.seconds = 3600 }
            return entry
        }
        return AutoUnlockEntry(seconds: tag, atMinutes: nil, custom: false)
    }

    // MARK: A length entered by hand

    static func hoursAndMinutes(of seconds: Int) -> (hours: Int, minutes: Int) {
        let s = min(max(seconds, 0), maxCustomSeconds)
        return (s / 3600, (s % 3600) / 60)
    }

    /// 24 hours is the end of the range: at 24 there are no minutes.
    static func length(hours: Int, minutes: Int) -> Int {
        let h = min(max(hours, 0), 24)
        let m = h == 24 ? 0 : min(max(minutes, 0), 59)
        return min(max(h * 3600 + m * 60, minCustomSeconds), maxCustomSeconds)
    }

    // MARK: Switching between a length and a time of day

    /// From a length to "Until": the time of day that length ends at, as of `now`.
    func switchedToClock(now: Date, calendar: Calendar = .current) -> AutoUnlockEntry {
        var entry = self
        let end = LockConfiguration.unlockDate(from: now, seconds: max(seconds, Self.minCustomSeconds))
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        entry.atMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        entry.custom = true
        return entry
    }

    /// From "Until" to "For": the length until that time, as of `now`.
    func switchedToLength(now: Date, calendar: Calendar = .current) -> AutoUnlockEntry {
        var entry = self
        if let at = atMinutes {
            entry.seconds = min(max(LockConfiguration.secondsUntil(minutesOfDay: at, from: now, calendar: calendar) / 60 * 60,
                                    Self.minCustomSeconds), Self.maxCustomSeconds)
        }
        entry.atMinutes = nil
        entry.custom = true
        return entry
    }

    // MARK: When it ends

    /// The moment a lock that starts at `now` ends, nil without a timer.
    func unlockDate(now: Date, calendar: Calendar = .current) -> Date? {
        if let at = atMinutes {
            return LockConfiguration.unlockDate(from: now, seconds: LockConfiguration.secondsUntil(minutesOfDay: at, from: now, calendar: calendar))
        }
        return seconds > 0 ? LockConfiguration.unlockDate(from: now, seconds: seconds) : nil
    }

    /// "23:30", or "Wed 07:30" when that is not today.
    static func endTitle(_ end: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if calendar.isDate(end, inSameDayAs: now) { return end.formatted(style) }
        var withDay = Date.FormatStyle().weekday(.abbreviated).hour().minute().locale(locale)
        withDay.calendar = calendar
        withDay.timeZone = calendar.timeZone
        return end.formatted(withDay)
    }
}

/// The auto-unlock choice, in the panel and in Settings: the lengths up to a day, and
/// "Custom…" for any length or a time of day. One setting, so the two places always agree.
struct AutoUnlockControl: View {
    enum Style { case panel, settings }

    let style: Style
    /// The lock will freeze the mouse: no "Off" is offered, because the menu bar icon cannot be clicked.
    let mouseFrozen: Bool

    @AppStorage(LockConfiguration.Key.autoUnlockSeconds) private var seconds = 0
    @AppStorage(LockConfiguration.Key.autoUnlockAtMinutes) private var atMinutes = -1
    @AppStorage(LockConfiguration.Key.autoUnlockCustom) private var custom = false
    @Environment(\.locale) private var locale

    private var entry: AutoUnlockEntry {
        get { AutoUnlockEntry(seconds: seconds, atMinutes: atMinutes >= 0 ? atMinutes : nil, custom: custom) }
        nonmutating set {
            seconds = newValue.seconds
            atMinutes = newValue.atMinutes ?? -1
            custom = newValue.custom
        }
    }

    private var selection: Binding<Int> {
        Binding(
            get: { entry.selection(mouseFrozen: mouseFrozen) },
            set: { entry = entry.choosing($0) }
        )
    }

    private var showsEntryBox: Bool {
        entry.selection(mouseFrozen: mouseFrozen) == AutoUnlockEntry.customTag
    }

    var body: some View {
        VStack(alignment: style == .panel ? .center : .leading, spacing: 6) {
            HStack(spacing: style == .panel ? 6 : 0) {
                label
                if style == .settings { Spacer() }
                picker
            }
            if showsEntryBox { entryBox }
        }
        .animation(.easeInOut(duration: 0.15), value: showsEntryBox)
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .panel:
            Label("Auto-unlock", systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .settings:
            Text("Auto-unlock")
                .font(.callout)
        }
    }

    private var picker: some View {
        Picker("Auto-unlock", selection: selection) {
            ForEach(LockConfiguration.offeredChoices(mouseLocked: mouseFrozen), id: \.self) { s in
                title(for: s).tag(s)
            }
            Divider()
            Text("Custom…").tag(AutoUnlockEntry.customTag)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }

    @ViewBuilder
    private func title(for seconds: Int) -> some View {
        if seconds == 0 {
            Text("Off")
        } else {
            Text(LockConfiguration.unlockChoiceTitle(seconds, locale: locale))
        }
    }

    // MARK: The entry box

    private var entryBox: some View {
        VStack(spacing: 6) {
            Picker("Auto-unlock", selection: kind) {
                Text("For").tag(false)
                Text("Until").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            if entry.isClock {
                DatePicker("Until", selection: clockTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .controlSize(.small)
            } else {
                HStack(spacing: 10) {
                    Stepper(value: hours, in: 0...24) {
                        Text(unit(entry.seconds / 3600 * 3600, unit: .hours))
                            .monospacedDigit()
                    }
                    .accessibilityLabel(Text("Hours"))
                    Stepper(value: minutes, in: 0...59) {
                        Text(unit((entry.seconds % 3600) / 60 * 60, unit: .minutes))
                            .monospacedDigit()
                    }
                    .accessibilityLabel(Text("Minutes"))
                }
                .controlSize(.small)
                .fixedSize()
            }

            if let end = entry.unlockDate(now: Date()) {
                Text("Unlocks at \(AutoUnlockEntry.endTitle(end, now: Date(), locale: locale))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(style == .panel ? .caption : .callout)
        .padding(.top, 2)
    }

    private var kind: Binding<Bool> {
        Binding(
            get: { entry.isClock },
            set: { wantsClock in
                if wantsClock == entry.isClock { return }
                entry = wantsClock ? entry.switchedToClock(now: Date()) : entry.switchedToLength(now: Date())
            }
        )
    }

    private var hours: Binding<Int> {
        Binding(
            get: { AutoUnlockEntry.hoursAndMinutes(of: entry.seconds).hours },
            set: { h in
                var e = entry
                e.seconds = AutoUnlockEntry.length(hours: h, minutes: AutoUnlockEntry.hoursAndMinutes(of: e.seconds).minutes)
                e.custom = true
                entry = e
            }
        )
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { AutoUnlockEntry.hoursAndMinutes(of: entry.seconds).minutes },
            set: { m in
                var e = entry
                e.seconds = AutoUnlockEntry.length(hours: AutoUnlockEntry.hoursAndMinutes(of: e.seconds).hours, minutes: m)
                e.custom = true
                entry = e
            }
        )
    }

    private var clockTime: Binding<Date> {
        Binding(
            get: {
                let at = entry.atMinutes ?? 0
                return Calendar.current.date(bySettingHour: at / 60, minute: at % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var e = entry
                e.atMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                e.custom = true
                entry = e
            }
        )
    }

    /// "3 hr" or "15 min", also when it is zero.
    private func unit(_ seconds: Int, unit: Duration.UnitsFormatStyle.Unit) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [unit], width: .abbreviated, zeroValueUnits: .show(length: 1)).locale(locale))
    }
}
