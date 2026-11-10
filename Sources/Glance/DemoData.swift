import Foundation
import GlanceCore

/// QA only (`--qa-demo-data`): an invented set of calendars and events used
/// instead of EventKit, so screenshots and docs can be produced on a machine
/// with no calendar account and no personal data. Nothing here is read from
/// or written to the user's calendars.
enum DemoData {
    /// Stable identifiers so a selection saved against demo data keeps working.
    static let workID = "demo-work"
    static let personalID = "demo-personal"

    /// Writable, so Settings shows the same rows a user sees. Demo events are
    /// still read-only (`isEditable: false`), and saving one fails harmlessly in
    /// the repository because these calendar IDs are not in EventKit.
    static let calendars: [CalendarInfo] = [
        CalendarInfo(id: workID, title: "Work", sourceTitle: "Demo",
                     color: RGBA(hex: 0x1E66F5), allowsModifications: true),
        CalendarInfo(id: personalID, title: "Personal", sourceTitle: "Demo",
                     color: RGBA(hex: 0x40A02B), allowsModifications: true),
    ]

    private struct Spec {
        let day, hour, minute: Int
        let minutes: Int
        let title: String
        let personal: Bool
        let location: String?
        let meeting: String?
    }

    /// Fixed month so screenshots are reproducible regardless of the date.
    static let year = 2026
    static let month = 3

    private static let specs: [Spec] = [
        Spec(day: 2, hour: 9, minute: 0, minutes: 60, title: "Design review", personal: false,
             location: nil, meeting: nil),
        Spec(day: 2, hour: 13, minute: 30, minutes: 60, title: "Lunch with Priya", personal: true,
             location: "Café Mila", meeting: nil),
        Spec(day: 3, hour: 10, minute: 0, minutes: 90, title: "Sprint planning", personal: false,
             location: nil, meeting: "https://zoom.us/j/1234567890"),
        Spec(day: 6, hour: 15, minute: 0, minutes: 45, title: "Dentist", personal: true,
             location: "Bridge Street Dental", meeting: nil),
        Spec(day: 9, hour: 8, minute: 30, minutes: 30, title: "Standup", personal: false,
             location: nil, meeting: "https://meet.google.com/abc-defg-hij"),
        Spec(day: 9, hour: 11, minute: 0, minutes: 120, title: "Write release notes", personal: false,
             location: nil, meeting: nil),
        Spec(day: 9, hour: 16, minute: 0, minutes: 60, title: "Coffee with Sam", personal: true,
             location: "Roastery", meeting: nil),
        Spec(day: 10, hour: 9, minute: 0, minutes: 60, title: "Roadmap workshop", personal: false,
             location: "Room 2", meeting: "https://zoom.us/j/9876543210"),
        Spec(day: 10, hour: 14, minute: 0, minutes: 60, title: "1:1 with Dana", personal: false,
             location: nil, meeting: nil),
        Spec(day: 13, hour: 10, minute: 0, minutes: 60, title: "Retro", personal: false,
             location: nil, meeting: nil),
        Spec(day: 16, hour: 12, minute: 0, minutes: 60, title: "Team lunch", personal: true,
             location: "The Old Kitchen", meeting: nil),
        Spec(day: 18, hour: 10, minute: 0, minutes: 45, title: "Review PRs", personal: false,
             location: nil, meeting: nil),
        Spec(day: 20, hour: 9, minute: 30, minutes: 60, title: "All hands", personal: false,
             location: nil, meeting: "https://zoom.us/j/5555555555"),
        Spec(day: 23, hour: 11, minute: 0, minutes: 60, title: "Pair session", personal: false,
             location: nil, meeting: nil),
        Spec(day: 25, hour: 18, minute: 30, minutes: 120, title: "Kateri's birthday dinner", personal: true,
             location: "Sardine", meeting: nil),
        Spec(day: 27, hour: 14, minute: 0, minutes: 60, title: "Quarterly planning", personal: false,
             location: nil, meeting: nil),
    ]

    /// Events for one month, bucketed by day. Mirrors the shape the repository
    /// returns so the rest of the app is unchanged.
    static func events(in month: MonthKey, calendarIDs: Set<String>?, calendar: Calendar) -> [DayKey: [EventSnapshot]] {
        guard month.year == year, month.month == self.month else { return [:] }
        var out: [DayKey: [EventSnapshot]] = [:]
        for (index, spec) in specs.enumerated() {
            let isPersonal = spec.personal
            if let ids = calendarIDs, !ids.contains(isPersonal ? personalID : workID) { continue }
            var comps = DateComponents()
            comps.year = year
            comps.month = self.month
            comps.day = spec.day
            comps.hour = spec.hour
            comps.minute = spec.minute
            guard let start = calendar.date(from: comps) else { continue }
            let end = start.addingTimeInterval(TimeInterval(spec.minutes * 60))
            let key = DayKey(date: start, calendar: calendar)
            out[key, default: []].append(EventSnapshot(
                eventIdentifier: "demo-\(index)",
                title: spec.title,
                start: start,
                end: end,
                calendarID: isPersonal ? personalID : workID,
                calendarTitle: isPersonal ? "Personal" : "Work",
                color: isPersonal ? RGBA(hex: 0x40A02B) : RGBA(hex: 0x1E66F5),
                location: spec.location,
                meetingURL: spec.meeting.flatMap(URL.init(string:)),
                isEditable: false
            ))
        }
        for key in out.keys {
            out[key]?.sort { $0.start < $1.start }
        }
        return out
    }
}
