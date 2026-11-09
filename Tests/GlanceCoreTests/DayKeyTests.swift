import XCTest
@testable import GlanceCore

final class DayKeyTests: XCTestCase {
    func testJulianRoundTripAcrossCenturies() {
        for j in stride(from: 2_300_000, to: 2_600_000, by: 997) {
            XCTAssertEqual(DayKey(julian: j).julian, j)
        }
        XCTAssertEqual(DayKey(year: 2000, month: 1, day: 1).julian, 2_451_545)
    }

    func testWeekdayMatchesFoundation() {
        let cal = gregorian()
        var day = DayKey(year: 2026, month: 1, day: 1)
        for _ in 0..<800 {
            XCTAssertEqual(day.weekday, cal.component(.weekday, from: day.startDate(in: cal)), "\(day)")
            day = day.adding(days: 1)
        }
    }

    func testAddingDaysCrossesLeapFebruary() {
        XCTAssertEqual(DayKey(year: 2028, month: 2, day: 28).adding(days: 1), DayKey(year: 2028, month: 2, day: 29))
        XCTAssertEqual(DayKey(year: 2027, month: 2, day: 28).adding(days: 1), DayKey(year: 2027, month: 3, day: 1))
        XCTAssertEqual(DayKey(year: 2026, month: 12, day: 31).adding(days: 1), DayKey(year: 2027, month: 1, day: 1))
    }

    func testStartDateHandlesDSTTransitionDays() {
        let cal = gregorian()
        let springForward = DayKey(year: 2026, month: 3, day: 8)
        let start = springForward.startDate(in: cal)
        XCTAssertEqual(DayKey(date: start, calendar: cal), springForward)
        XCTAssertEqual(springForward.adding(days: 1).startDate(in: cal).timeIntervalSince(start), 23 * 3600)
    }

    func testMonthKeyNormalisesAndCountsDays() {
        XCTAssertEqual(MonthKey(year: 2026, month: 13), MonthKey(year: 2027, month: 1))
        XCTAssertEqual(MonthKey(year: 2026, month: 0), MonthKey(year: 2025, month: 12))
        XCTAssertEqual(MonthKey(year: 2026, month: 1).adding(months: -13), MonthKey(year: 2024, month: 12))
        XCTAssertEqual(MonthKey(year: 2028, month: 2).numberOfDays, 29)
        XCTAssertEqual(MonthKey(year: 2100, month: 2).numberOfDays, 28)
        XCTAssertEqual(MonthKey(year: 2026, month: 4).lastDay, DayKey(year: 2026, month: 4, day: 30))
    }

    func testMonthsCovering() {
        let ms = MonthKey.months(covering: DayKey(year: 2026, month: 11, day: 29), DayKey(year: 2027, month: 1, day: 3))
        XCTAssertEqual(ms, [MonthKey(year: 2026, month: 11), MonthKey(year: 2026, month: 12), MonthKey(year: 2027, month: 1)])
    }

    func testWeekdaySet() {
        let s = WeekdaySet(weekdays: [1, 7])
        XCTAssertEqual(s, .weekend)
        XCTAssertTrue(s.contains(weekday: 1))
        XCTAssertFalse(s.contains(weekday: 2))
        XCTAssertTrue(s.contains(weekday: 7))
    }
}

final class MonthGridTests: XCTestCase {
    func testSundayStartGrid() {
        // November 2026 starts on a Sunday.
        let g = MonthGrid(month: MonthKey(year: 2026, month: 11), firstWeekday: 1)
        XCTAssertEqual(g.days.count, 42)
        XCTAssertEqual(g.firstDay, DayKey(year: 2026, month: 11, day: 1))
        XCTAssertEqual(g.lastDay, DayKey(year: 2026, month: 12, day: 12))
        XCTAssertEqual(g.index(of: DayKey(year: 2026, month: 11, day: 9)), 8)
    }

    func testMondayStartGridLeadsWithPreviousMonth() {
        let g = MonthGrid(month: MonthKey(year: 2026, month: 11), firstWeekday: 2)
        XCTAssertEqual(g.firstDay, DayKey(year: 2026, month: 10, day: 26))
        XCTAssertFalse(g.isInMonth(g.firstDay))
        XCTAssertEqual(g.weekday(forColumn: 0), 2)
        XCTAssertEqual(g.weekday(forColumn: 6), 1)
        XCTAssertEqual(g.column(forWeekday: 1), 6)
    }

    func testEveryColumnHasConsistentWeekday() {
        for fw in 1...7 {
            for m in 1...12 {
                let g = MonthGrid(month: MonthKey(year: 2027, month: m), firstWeekday: fw)
                for (i, d) in g.days.enumerated() {
                    XCTAssertEqual(d.weekday, g.weekday(forColumn: i % 7))
                }
                XCTAssertTrue(g.index(of: g.month.firstDay)! < 7)
            }
        }
    }

    func testInvalidFirstWeekdayFallsBackToSunday() {
        XCTAssertEqual(MonthGrid(month: MonthKey(year: 2026, month: 1), firstWeekday: 9).firstWeekday, 1)
    }

    func testISOWeekNumbersMatchFoundation() {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(identifier: "UTC")!
        var day = DayKey(year: 2020, month: 12, day: 20)
        for _ in 0..<(366 * 3) {
            let d = iso.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
            XCTAssertEqual(WeekNumber.iso(day), iso.component(.weekOfYear, from: d), "\(day)")
            day = day.adding(days: 1)
        }
    }

    func testSundayStartWeekNumbersMatchUSCalendar() {
        var us = Calendar(identifier: .gregorian)
        us.timeZone = TimeZone(identifier: "UTC")!
        us.firstWeekday = 1
        us.minimumDaysInFirstWeek = 1
        var day = DayKey(year: 2020, month: 12, day: 20)
        for _ in 0..<(366 * 3) {
            let d = us.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
            XCTAssertEqual(WeekNumber.of(day, firstWeekday: 1), us.component(.weekOfYear, from: d), "\(day)")
            day = day.adding(days: 1)
        }
    }

    func testGridWeekNumbers() {
        let g = MonthGrid(month: MonthKey(year: 2027, month: 1), firstWeekday: 2)
        // 2027-01-01 is a Friday; ISO week 53 of 2026.
        XCTAssertEqual(g.weekNumbers().first, 53)
        XCTAssertEqual(g.weekNumbers()[1], 1)
    }
}

final class DaySpanTests: XCTestCase {
    let cal = gregorian()

    func testTimedEventWithinOneDay() {
        XCTAssertEqual(DaySpan.days(start: date(2026, 11, 9, 9), end: date(2026, 11, 9, 10), calendar: cal),
                       [DayKey(year: 2026, month: 11, day: 9)])
    }

    func testEndingAtMidnightDoesNotSpill() {
        let days = DaySpan.days(start: date(2026, 11, 9), end: date(2026, 11, 10), calendar: cal)
        XCTAssertEqual(days, [DayKey(year: 2026, month: 11, day: 9)])
    }

    func testOvernightAndClipping() {
        let days = DaySpan.days(start: date(2026, 11, 9, 22), end: date(2026, 11, 12, 2), calendar: cal)
        XCTAssertEqual(days.count, 4)
        let clipped = DaySpan.days(start: date(2026, 11, 9, 22), end: date(2026, 11, 12, 2), calendar: cal,
                                   clippedTo: DayKey(year: 2026, month: 11, day: 10)...DayKey(year: 2026, month: 11, day: 11))
        XCTAssertEqual(clipped, [DayKey(year: 2026, month: 11, day: 10), DayKey(year: 2026, month: 11, day: 11)])
        XCTAssertEqual(DaySpan.days(start: date(2026, 1, 1), end: date(2026, 1, 2), calendar: cal,
                                    clippedTo: DayKey(year: 2026, month: 2, day: 1)...DayKey(year: 2026, month: 2, day: 2)), [])
    }

    func testZeroLengthEventTouchesStartDay() {
        XCTAssertEqual(DaySpan.days(start: date(2026, 11, 9, 12), end: date(2026, 11, 9, 12), calendar: cal),
                       [DayKey(year: 2026, month: 11, day: 9)])
    }
}
