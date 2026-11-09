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

    private func grid(_ y: Int, _ m: Int, _ fw: Int) -> MonthGrid { MonthGrid(month: MonthKey(year: y, month: m), firstWeekday: fw) }

    /// Rows holding days of the month (the rest of the 6 laid-out rows stay empty).
    private func dayRows(_ g: MonthGrid) -> Int { (0..<MonthGrid.rows).filter(g.rowHasDays).count }

    func testFourWeekFebruary() {
        // 1 Feb 2026 is a Sunday and February has 28 days.
        let g = grid(2026, 2, 1)
        XCTAssertEqual(g.leadingBlanks, 0)
        XCTAssertEqual(dayRows(g), 4)
        XCTAssertEqual(g.visibleDay(at: 27), DayKey(year: 2026, month: 2, day: 28))
        for i in 28..<42 { XCTAssertNil(g.visibleDay(at: i), "\(i)") }
        XCTAssertFalse(g.rowHasDays(4))
        XCTAssertFalse(g.rowHasDays(5))
        // Monday start pushes the 1st to the last column: 5 weeks.
        XCTAssertEqual(grid(2026, 2, 2).leadingBlanks, 6)
        XCTAssertEqual(dayRows(grid(2026, 2, 2)), 5)
    }

    func testFiveWeekNovember() {
        // November 2026 with a Sunday start ends on Monday 30 in row 5; the
        // sixth row (6–12 Dec) is laid out but empty.
        let g = grid(2026, 11, 1)
        XCTAssertEqual(dayRows(g), 5)
        XCTAssertTrue(g.isInMonth(index: 29))
        for i in 30..<42 { XCTAssertFalse(g.isInMonth(index: i), "\(i)") }
        XCTAssertNil(g.visibleDay(at: 30))
        // Monday start leads with six October slots and needs 6 weeks.
        let m = grid(2026, 11, 2)
        XCTAssertEqual(dayRows(m), 6)
        for i in 0..<6 { XCTAssertNil(m.visibleDay(at: i)) }
        XCTAssertEqual(m.visibleDay(at: 6), DayKey(year: 2026, month: 11, day: 1))
    }

    func testSixWeekAugust() {
        // 1 Aug 2026 is a Saturday; 31 days spill into a sixth row.
        XCTAssertEqual(dayRows(grid(2026, 8, 1)), 6)
        XCTAssertEqual(grid(2026, 8, 1).visibleDay(at: 36), DayKey(year: 2026, month: 8, day: 31))
        XCTAssertEqual(dayRows(grid(2026, 8, 2)), 6)
    }

    func testBlankIndicesAreTheGapsInVisibleRows() {
        // August 2026, Sunday start: six leading blanks (Sat 1st), 31 days, five trailing.
        XCTAssertEqual(grid(2026, 8, 1).blankIndices, Array(0..<6) + Array(37..<42))
        // February 2026, Sunday start: exactly four full weeks, no gaps.
        XCTAssertEqual(grid(2026, 2, 1).blankIndices, [])
        for fw in 1...7 {
            for m in 1...12 {
                let g = grid(2026, m, fw)
                XCTAssertEqual(g.blankIndices.count, g.visibleRows * 7 - g.month.numberOfDays)
                XCTAssertTrue(g.blankIndices.allSatisfy { $0 / 7 < g.visibleRows && !g.isInMonth(index: $0) })
            }
        }
    }

    func testRowsWithDaysAreLeadingAndContiguous() {
        for fw in 1...7 {
            for y in 2025...2028 {
                for m in 1...12 {
                    let g = grid(y, m, fw)
                    let n = dayRows(g)
                    XCTAssertTrue((4...6).contains(n))
                    XCTAssertEqual(g.visibleRows, n)
                    // Days fill the first n rows; any later rows are wholly empty.
                    for row in 0..<MonthGrid.rows { XCTAssertEqual(g.rowHasDays(row), row < n, "\(y)-\(m) fw\(fw) row \(row)") }
                    for i in 0..<42 { XCTAssertEqual(g.isInMonth(index: i), g.isInMonth(g.days[i])) }
                    XCTAssertEqual((0..<42).filter(g.isInMonth(index:)).count, g.month.numberOfDays)
                }
            }
        }
    }

    func testWeekNumbersOnlyForRowsWithDays() {
        // Sunday start: Feb 2026 has 4 weeks, Nov 5, Aug 6; Monday start: 5, 6, 6.
        for (m, fw, rows) in [(2, 1, 4), (11, 1, 5), (8, 1, 6), (2, 2, 5), (11, 2, 6), (8, 2, 6)] {
            let g = grid(2026, m, fw)
            let numbers = g.weekNumbers()
            XCTAssertEqual(numbers.count, rows, "2026-\(m) fw\(fw)")
            XCTAssertEqual(numbers, (0..<rows).map { WeekNumber.of(g.days[$0 * 7], firstWeekday: fw) })
        }
        // Feb 2026, Sunday start: weeks 6–9; the empty fifth and sixth rows get no number.
        XCTAssertEqual(grid(2026, 2, 1).weekNumbers(), [6, 7, 8, 9])
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
