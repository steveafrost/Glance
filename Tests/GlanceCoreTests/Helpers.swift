import Foundation
@testable import GlanceCore

func gregorian(_ tz: String = "America/New_York") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0,
          cal: Calendar = gregorian()) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, meeting: String? = nil,
           calendarTitle: String = "Work") -> EventSnapshot {
    EventSnapshot(eventIdentifier: id, title: id, start: start, end: end, isAllDay: allDay,
                  calendarTitle: calendarTitle, meetingURL: meeting.flatMap(URL.init(string:)))
}
