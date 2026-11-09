import Foundation

/// An sRGB colour that can cross concurrency domains.
public struct RGBA: Hashable, Sendable, Codable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255)
    }
}

/// An immutable, Sendable copy of the parts of an EKEvent the UI needs.
public struct EventSnapshot: Hashable, Sendable, Identifiable {
    /// Unique per occurrence: eventIdentifier + occurrence start.
    public var id: String { "\(eventIdentifier)|\(occurrenceStart.timeIntervalSinceReferenceDate)" }
    public var eventIdentifier: String
    public var occurrenceStart: Date
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var color: RGBA
    public var location: String?
    public var url: URL?
    public var notes: String?
    public var meetingURL: URL?
    public var isRecurring: Bool
    public var isEditable: Bool

    public init(eventIdentifier: String, occurrenceStart: Date? = nil, title: String, start: Date, end: Date,
                isAllDay: Bool = false, calendarID: String = "cal", calendarTitle: String = "Calendar",
                color: RGBA = RGBA(hex: 0x1E66F5), location: String? = nil, url: URL? = nil,
                notes: String? = nil, meetingURL: URL? = nil, isRecurring: Bool = false, isEditable: Bool = true) {
        self.eventIdentifier = eventIdentifier
        self.occurrenceStart = occurrenceStart ?? start
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.color = color
        self.location = location
        self.url = url
        self.notes = notes
        self.meetingURL = meetingURL
        self.isRecurring = isRecurring
        self.isEditable = isEditable
    }
}

public struct CalendarInfo: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public var color: RGBA
    public var allowsModifications: Bool
    public init(id: String, title: String, sourceTitle: String, color: RGBA, allowsModifications: Bool) {
        self.id = id; self.title = title; self.sourceTitle = sourceTitle
        self.color = color; self.allowsModifications = allowsModifications
    }
}

public struct CalendarSourceGroup: Hashable, Sendable {
    public var title: String
    public var calendars: [CalendarInfo]
}

public enum CalendarGrouping {
    /// Group calendars by source, sources and calendars sorted by title.
    public static func group(_ calendars: [CalendarInfo]) -> [CalendarSourceGroup] {
        let bySource = Dictionary(grouping: calendars, by: \.sourceTitle)
        return bySource.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { source in
            CalendarSourceGroup(title: source, calendars: bySource[source]!.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            })
        }
    }
}

/// Day-bucketed events, all-day first (by calendar title), then by start.
public enum EventBucketing {
    public static func bucket(_ events: [EventSnapshot], calendar: Calendar,
                              range: ClosedRange<DayKey>) -> [DayKey: [EventSnapshot]] {
        var result: [DayKey: [EventSnapshot]] = [:]
        for event in events {
            for day in DaySpan.days(start: event.start, end: event.end, calendar: calendar, clippedTo: range) {
                result[day, default: []].append(event)
            }
        }
        for key in result.keys {
            result[key]!.sort { a, b in
                let aAll = treatsAsAllDay(a, on: key, calendar: calendar)
                let bAll = treatsAsAllDay(b, on: key, calendar: calendar)
                if aAll != bAll { return aAll }
                if aAll { return a.calendarTitle.localizedStandardCompare(b.calendarTitle) == .orderedAscending }
                if a.start != b.start { return a.start < b.start }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
        return result
    }

    /// True all-day events, and timed events that cover the whole of `day`.
    public static func treatsAsAllDay(_ e: EventSnapshot, on day: DayKey, calendar: Calendar) -> Bool {
        if e.isAllDay { return true }
        let dayStart = day.startDate(in: calendar)
        let next = day.adding(days: 1).startDate(in: calendar)
        return e.start <= dayStart && e.end >= next
    }
}
