import Foundation
import GlanceCore

/// Typed access to UserDefaults. Setting a value posts `didChange`.
@MainActor
final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("GlancePreferencesDidChange")

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case theme, firstWeekday, highlightedWeekdays, showWeekNumbers, showEventDots
        case clockFormat, hideIcon, iconStyle, iconOpticalOffset, hotKey
        case selectedCalendarIDs, agendaDays, showEmptyAgendaDays
        case showMeetingIndicator, meetingLeadMinutes, alwaysTopRight
    }

    private init() {
        defaults.register(defaults: [
            Key.theme.rawValue: ThemeChoice.catppuccinAuto.rawValue,
            Key.firstWeekday.rawValue: 0, // 0 = follow the system
            Key.highlightedWeekdays.rawValue: WeekdaySet.weekend.rawValue,
            Key.showWeekNumbers.rawValue: false,
            Key.showEventDots.rawValue: true,
            Key.clockFormat.rawValue: "",
            Key.hideIcon.rawValue: false,
            Key.iconStyle.rawValue: IconLayout.Style.outline.rawValue,
            Key.iconOpticalOffset.rawValue: 0.0,
            Key.agendaDays.rawValue: 7,
            Key.showEmptyAgendaDays.rawValue: false,
            Key.showMeetingIndicator.rawValue: true,
            Key.meetingLeadMinutes.rawValue: 5,
            Key.alwaysTopRight.rawValue: false,
        ])
    }

    private func changed(_ key: Key) {
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["key": key.rawValue])
    }

    var theme: ThemeChoice {
        get { ThemeChoice(rawValue: defaults.string(forKey: Key.theme.rawValue) ?? "") ?? .catppuccinAuto }
        set { defaults.set(newValue.rawValue, forKey: Key.theme.rawValue); changed(.theme) }
    }

    /// 0 = system; else 1 = Sunday ... 7 = Saturday.
    var firstWeekdaySetting: Int {
        get { defaults.integer(forKey: Key.firstWeekday.rawValue) }
        set { defaults.set(newValue, forKey: Key.firstWeekday.rawValue); changed(.firstWeekday) }
    }

    var firstWeekday: Int {
        let s = firstWeekdaySetting
        return (1...7).contains(s) ? s : Calendar.autoupdatingCurrent.firstWeekday
    }

    var highlightedWeekdays: WeekdaySet {
        get { WeekdaySet(rawValue: defaults.integer(forKey: Key.highlightedWeekdays.rawValue)) }
        set { defaults.set(newValue.rawValue, forKey: Key.highlightedWeekdays.rawValue); changed(.highlightedWeekdays) }
    }

    var showWeekNumbers: Bool {
        get { defaults.bool(forKey: Key.showWeekNumbers.rawValue) }
        set { defaults.set(newValue, forKey: Key.showWeekNumbers.rawValue); changed(.showWeekNumbers) }
    }

    var showEventDots: Bool {
        get { defaults.bool(forKey: Key.showEventDots.rawValue) }
        set { defaults.set(newValue, forKey: Key.showEventDots.rawValue); changed(.showEventDots) }
    }

    var clockFormat: String {
        get { defaults.string(forKey: Key.clockFormat.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.clockFormat.rawValue); changed(.clockFormat) }
    }

    var hideIcon: Bool {
        get { defaults.bool(forKey: Key.hideIcon.rawValue) }
        set { defaults.set(newValue, forKey: Key.hideIcon.rawValue); changed(.hideIcon) }
    }

    var iconStyle: IconLayout.Style {
        get { IconLayout.Style(rawValue: defaults.string(forKey: Key.iconStyle.rawValue) ?? "") ?? .outline }
        set { defaults.set(newValue.rawValue, forKey: Key.iconStyle.rawValue); changed(.iconStyle) }
    }

    /// Hidden tuning knob (`defaults write <bundle id> iconOpticalOffset -float 1`).
    var iconOpticalOffset: Double { defaults.double(forKey: Key.iconOpticalOffset.rawValue) }

    var hotKey: KeyCombo? {
        get {
            guard let data = defaults.data(forKey: Key.hotKey.rawValue) else { return nil }
            return try? JSONDecoder().decode(KeyCombo.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.hotKey.rawValue)
            } else {
                defaults.removeObject(forKey: Key.hotKey.rawValue)
            }
            changed(.hotKey)
        }
    }

    /// Nil means every calendar is shown (the default until the user chooses).
    var selectedCalendarIDs: Set<String>? {
        get { defaults.stringArray(forKey: Key.selectedCalendarIDs.rawValue).map(Set.init) }
        set {
            if let newValue { defaults.set(newValue.sorted(), forKey: Key.selectedCalendarIDs.rawValue) }
            else { defaults.removeObject(forKey: Key.selectedCalendarIDs.rawValue) }
            changed(.selectedCalendarIDs)
        }
    }

    var agendaDays: Int {
        get { min(max(defaults.integer(forKey: Key.agendaDays.rawValue), 1), 31) }
        set { defaults.set(newValue, forKey: Key.agendaDays.rawValue); changed(.agendaDays) }
    }

    var showEmptyAgendaDays: Bool {
        get { defaults.bool(forKey: Key.showEmptyAgendaDays.rawValue) }
        set { defaults.set(newValue, forKey: Key.showEmptyAgendaDays.rawValue); changed(.showEmptyAgendaDays) }
    }

    var showMeetingIndicator: Bool {
        get { defaults.bool(forKey: Key.showMeetingIndicator.rawValue) }
        set { defaults.set(newValue, forKey: Key.showMeetingIndicator.rawValue); changed(.showMeetingIndicator) }
    }

    var meetingLeadMinutes: Int {
        get { min(max(defaults.integer(forKey: Key.meetingLeadMinutes.rawValue), 0), 60) }
        set { defaults.set(newValue, forKey: Key.meetingLeadMinutes.rawValue); changed(.meetingLeadMinutes) }
    }

    var alwaysTopRight: Bool {
        get { defaults.bool(forKey: Key.alwaysTopRight.rawValue) }
        set { defaults.set(newValue, forKey: Key.alwaysTopRight.rawValue); changed(.alwaysTopRight) }
    }

    nonisolated static func key(of note: Notification) -> String? { note.userInfo?["key"] as? String }
}
