import Foundation

/// The days shown for one month: always 6 rows of 7, so the grid's
/// height never changes when the month does.
public struct MonthGrid: Sendable, Equatable {
    public static let rows = 6
    public static let columns = 7

    public let month: MonthKey
    /// 1 = Sunday ... 7 = Saturday.
    public let firstWeekday: Int
    public let days: [DayKey]

    public init(month: MonthKey, firstWeekday: Int) {
        let fw = (1...7).contains(firstWeekday) ? firstWeekday : 1
        self.month = month
        self.firstWeekday = fw
        let first = month.firstDay
        let lead = (first.weekday - fw + 7) % 7
        let start = first.adding(days: -lead)
        self.days = (0..<(Self.rows * Self.columns)).map { start.adding(days: $0) }
    }

    public var firstDay: DayKey { days[0] }
    public var lastDay: DayKey { days[days.count - 1] }

    public func index(of day: DayKey) -> Int? {
        let i = firstDay.days(until: day)
        return (0..<days.count).contains(i) ? i : nil
    }

    public func isInMonth(_ day: DayKey) -> Bool { day.year == month.year && day.month == month.month }

    /// Weekday (1 = Sunday) shown in `column`.
    public func weekday(forColumn column: Int) -> Int { (firstWeekday - 1 + column) % 7 + 1 }

    public func column(forWeekday weekday: Int) -> Int { (weekday - firstWeekday + 7) % 7 }

    /// Week numbers for each row. Monday-start grids use ISO 8601
    /// numbering; other starts count the week containing 1 January as week 1.
    public func weekNumbers() -> [Int] {
        (0..<Self.rows).map { WeekNumber.of(days[$0 * Self.columns], firstWeekday: firstWeekday) }
    }
}

public enum WeekNumber {
    /// Week of year for the week (starting on `firstWeekday`) that contains `day`.
    public static func of(_ day: DayKey, firstWeekday: Int) -> Int {
        if firstWeekday == 2 { return iso(day) }
        // Week 1 contains 1 January; weeks start on firstWeekday.
        func weekStart(_ d: DayKey) -> DayKey { d.adding(days: -((d.weekday - firstWeekday + 7) % 7)) }
        let start = weekStart(day)
        // The week belongs to the year of its last day (so a week spanning
        // New Year is week 1 of the new year).
        let end = start.adding(days: 6)
        let year = end.year
        let week1 = weekStart(DayKey(year: year, month: 1, day: 1))
        return week1.days(until: start) / 7 + 1
    }

    /// ISO 8601 week number: the week containing the year's first Thursday is week 1.
    public static func iso(_ day: DayKey) -> Int {
        let isoWeekday = (day.weekday + 5) % 7 + 1 // Monday = 1 ... Sunday = 7
        let thursday = day.adding(days: 4 - isoWeekday)
        let jan1 = DayKey(year: thursday.year, month: 1, day: 1)
        return jan1.days(until: thursday) / 7 + 1
    }
}
