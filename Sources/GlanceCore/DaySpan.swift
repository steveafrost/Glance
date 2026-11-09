import Foundation

public enum DaySpan {
    /// The days an event touches, clipped to `range`. End dates are
    /// exclusive, so an event ending exactly at midnight does not spill
    /// into the next day. Zero-length events touch their start day.
    public static func days(start: Date, end: Date, calendar: Calendar,
                            clippedTo range: ClosedRange<DayKey>? = nil) -> [DayKey] {
        let first = DayKey(date: start, calendar: calendar)
        let effectiveEnd = end > start ? end.addingTimeInterval(-0.001) : start
        let last = DayKey(date: effectiveEnd, calendar: calendar)
        var lo = first, hi = last
        if let range {
            lo = max(lo, range.lowerBound)
            hi = min(hi, range.upperBound)
        }
        guard lo <= hi else { return [] }
        return (0...lo.days(until: hi)).map { lo.adding(days: $0) }
    }
}
