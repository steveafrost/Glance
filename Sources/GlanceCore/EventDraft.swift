import Foundation

/// Editable fields of an event, independent of EventKit.
public struct EventDraft: Equatable, Sendable {
    /// Nil for a new event.
    public var eventIdentifier: String?
    public var occurrenceStart: Date?
    public var isRecurring: Bool = false
    public var title: String
    public var isAllDay: Bool
    public var start: Date
    public var end: Date
    public var calendarID: String?
    public var location: String
    public var urlText: String
    public var notes: String

    public init(eventIdentifier: String? = nil, occurrenceStart: Date? = nil, isRecurring: Bool = false,
                title: String = "", isAllDay: Bool = false, start: Date, end: Date, calendarID: String?,
                location: String = "", urlText: String = "", notes: String = "") {
        self.eventIdentifier = eventIdentifier
        self.occurrenceStart = occurrenceStart
        self.isRecurring = isRecurring
        self.title = title
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.location = location
        self.urlText = urlText
        self.notes = notes
    }

    public var isNew: Bool { eventIdentifier == nil }

    /// A new event on `day`: the next whole hour if `day` is today, else
    /// 9:00, lasting an hour.
    public static func new(on day: DayKey, now: Date, calendar: Calendar, calendarID: String?) -> EventDraft {
        let start: Date
        if DayKey(date: now, calendar: calendar) == day,
           let next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime),
           DayKey(date: next, calendar: calendar) == day {
            start = next
        } else {
            start = calendar.date(byAdding: .hour, value: 9, to: day.startDate(in: calendar)) ?? day.startDate(in: calendar)
        }
        return EventDraft(start: start, end: start.addingTimeInterval(3600), calendarID: calendarID)
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case endBeforeStart
        case noCalendar
        case invalidURL(String)

        public var errorDescription: String? {
            switch self {
            case .endBeforeStart: "The event ends before it starts. Choose an end time after the start time."
            case .noCalendar: "Choose a calendar for this event."
            case .invalidURL(let text): "“\(text)” isn’t a valid web address. Use a full URL such as https://example.com."
            }
        }
    }

    public var url: URL? {
        let t = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let u = URL(string: t), let scheme = u.scheme, !scheme.isEmpty,
              u.host != nil || scheme != "http" && scheme != "https" else { return nil }
        return u
    }

    public var trimmedTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "New Event" : t
    }

    /// Dates as they should be saved: all-day events cover whole days.
    public func normalizedDates(calendar: Calendar) -> (start: Date, end: Date) {
        guard isAllDay else { return (start, end) }
        let first = DayKey(date: start, calendar: calendar)
        let last = max(first, DayKey(date: end, calendar: calendar))
        return (first.startDate(in: calendar), last.adding(days: 1).startDate(in: calendar))
    }

    public func validate(calendar: Calendar) -> ValidationError? {
        if calendarID == nil { return .noCalendar }
        let dates = normalizedDates(calendar: calendar)
        if dates.end < dates.start { return .endBeforeStart }
        let t = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, url == nil { return .invalidURL(t) }
        return nil
    }
}
