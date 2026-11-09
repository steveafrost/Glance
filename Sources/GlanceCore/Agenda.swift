import Foundation

public enum AgendaRow: Hashable, Sendable {
    case day(DayKey)
    case event(EventSnapshot, day: DayKey)
    case noEvents(DayKey)
}

public enum Agenda {
    /// Rows for `days` days starting at `start`. The first day always shows
    /// (with a "No events" row if empty); later days only when they have
    /// events, unless `showEmptyDays`.
    public static func rows(eventsByDay: [DayKey: [EventSnapshot]], start: DayKey, days: Int,
                            showEmptyDays: Bool = false) -> [AgendaRow] {
        var rows: [AgendaRow] = []
        for offset in 0..<max(1, days) {
            let day = start.adding(days: offset)
            let events = eventsByDay[day] ?? []
            if events.isEmpty {
                if offset == 0 || showEmptyDays { rows += [.day(day), .noEvents(day)] }
                continue
            }
            rows.append(.day(day))
            rows += events.map { .event($0, day: day) }
        }
        return rows
    }

    /// "All day", "9:00 AM – 10:00 AM", "Until 10:00 AM", or "From 9:00 PM"
    /// depending on how the event overlaps `day`.
    public static func timeText(for e: EventSnapshot, on day: DayKey, calendar: Calendar, locale: Locale) -> String {
        if EventBucketing.treatsAsAllDay(e, on: day, calendar: calendar) { return "All day" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateStyle = .none
        f.timeStyle = .short
        let startsToday = DayKey(date: e.start, calendar: calendar) == day
        let endsToday = DayKey(date: e.end.addingTimeInterval(e.end > e.start ? -0.001 : 0), calendar: calendar) == day
        switch (startsToday, endsToday) {
        case (true, true):
            return e.start == e.end ? f.string(from: e.start) : "\(f.string(from: e.start)) – \(f.string(from: e.end))"
        case (true, false): return "From \(f.string(from: e.start))"
        case (false, true): return "Until \(f.string(from: e.end))"
        case (false, false): return "All day"
        }
    }
}
