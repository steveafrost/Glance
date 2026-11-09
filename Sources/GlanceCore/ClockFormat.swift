import Foundation

/// What a custom `DateFormatter` pattern shows, used to decide how often
/// the menu bar clock must refresh.
public struct ClockFormat: Equatable, Sendable {
    public let pattern: String
    public let usesTime: Bool
    public let usesSeconds: Bool

    public init(_ pattern: String) {
        var usesTime = false, usesSeconds = false, quoted = false
        // '' is a literal quote; drop pairs first so they don't toggle quoting.
        for ch in pattern.replacingOccurrences(of: "''", with: "") {
            if ch == "'" { quoted.toggle(); continue }
            if quoted { continue }
            if "sSA".contains(ch) { usesSeconds = true; usesTime = true }
            else if "aHhKkjJCmBb".contains(ch) { usesTime = true }
        }
        self.pattern = pattern
        self.usesTime = usesTime
        self.usesSeconds = usesSeconds
    }

    public var isEmpty: Bool { pattern.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Next instant the displayed text can change: the next whole second
    /// or minute when the pattern shows time, else the next midnight.
    public func nextTick(after now: Date, calendar: Calendar) -> Date {
        if usesSeconds {
            return Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate + 0.0005).rounded(.down) + 1)
        }
        if usesTime {
            return calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
                ?? now.addingTimeInterval(60)
        }
        let today = DayKey(date: now, calendar: calendar)
        return today.adding(days: 1).startDate(in: calendar)
    }

    /// Dates that together exercise every month name, weekday name and
    /// AM/PM marker, with two-digit days and hours. Formatting each and
    /// taking the widest gives a width that holds all year.
    public static func sampleDates(year: Int = 2027, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        for month in 1...12 {
            for day in 22...28 { // seven consecutive days cover every weekday
                for hour in [10, 22] {
                    if let d = calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                                  hour: hour, minute: 58, second: 58)) {
                        dates.append(d)
                    }
                }
            }
        }
        return dates
    }

    /// Text whose rendered width (in a monospaced-digit font) is at least as
    /// wide as any value the pattern can produce today: every digit is
    /// replaced by "0", which is as wide as other tabular digits.
    public static func widthProbe(for text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }
}
