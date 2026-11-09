import Foundation

/// A calendar day (proleptic Gregorian), independent of time zone.
/// Arithmetic goes through the Julian Day Number, so adding days and
/// comparing are integer operations with no `Calendar` round-trips.
public struct DayKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Julian Day Number (Fliegel–Van Flandern).
    public var julian: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(julian j: Int) {
        let a = j + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.day = e - (153 * m + 2) / 5 + 1
        self.month = m + 3 - 12 * (m / 10)
        self.year = 100 * b + d - 4800 + m / 10
    }

    /// The day containing `date` in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar) -> Date {
        let comps = DateComponents(year: year, month: month, day: day)
        // A day always exists, but DST can skip midnight; startOfDay handles that.
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: noon)
    }

    public func adding(days n: Int) -> DayKey { DayKey(julian: julian + n) }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday)`.
    public var weekday: Int { (julian + 1) % 7 + 1 }

    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    public func days(until other: DayKey) -> Int { other.julian - julian }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.julian < rhs.julian }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

/// A calendar month.
public struct MonthKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        // Normalise so month is always 1...12.
        let zeroBased = year * 12 + (month - 1)
        self.year = Int((Double(zeroBased) / 12).rounded(.down))
        self.month = zeroBased - self.year * 12 + 1
    }

    public func adding(months n: Int) -> MonthKey { MonthKey(year: year, month: month + n) }

    public var firstDay: DayKey { DayKey(year: year, month: month, day: 1) }

    public var numberOfDays: Int {
        firstDay.days(until: adding(months: 1).firstDay)
    }

    public var lastDay: DayKey { firstDay.adding(days: numberOfDays - 1) }

    public var ordinal: Int { year * 12 + (month - 1) }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { lhs.ordinal < rhs.ordinal }

    /// Every month touched by the inclusive day range.
    public static func months(covering first: DayKey, _ last: DayKey) -> [MonthKey] {
        guard first <= last else { return [] }
        var result: [MonthKey] = []
        var m = first.monthKey
        while m <= last.monthKey { result.append(m); m = m.adding(months: 1) }
        return result
    }

    public var description: String { String(format: "%04d-%02d", year, month) }
}

/// A set of weekdays, bit n-1 for weekday n (1 = Sunday).
public struct WeekdaySet: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue & 0x7F }

    public init(weekdays: [Int]) {
        self.init(rawValue: weekdays.reduce(0) { $0 | (1 << (($1 - 1) % 7)) })
    }

    public func contains(weekday: Int) -> Bool { rawValue & (1 << ((weekday - 1) % 7)) != 0 }

    public static let weekend = WeekdaySet(weekdays: [1, 7])
    public static let none = WeekdaySet([])
}
