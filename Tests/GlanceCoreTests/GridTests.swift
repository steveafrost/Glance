import XCTest
@testable import GlanceCore

final class GridGeometryTests: XCTestCase {
    func testHitTestingRoundTrips() {
        let g = GridGeometry(showsWeekNumbers: true)
        for i in 0..<42 {
            let r = g.cellRect(index: i)
            XCTAssertEqual(g.index(at: CGPoint(x: r.midX, y: r.midY)), i)
        }
        XCTAssertNil(g.index(at: CGPoint(x: 5, y: 40)), "week number column")
        XCTAssertNil(g.index(at: CGPoint(x: 40, y: 5)), "header")
        XCTAssertNil(g.index(at: CGPoint(x: g.size.width + 1, y: 40)))
    }

    func testSizeAccountsForWeekColumn() {
        XCTAssertEqual(GridGeometry(showsWeekNumbers: false).size, CGSize(width: 231, height: 194))
        XCTAssertEqual(GridGeometry(showsWeekNumbers: true).size.width, 255)
        XCTAssertNil(GridGeometry(showsWeekNumbers: false).weekNumberRect(row: 0))
    }

    func testRowCountDrivesHeightAndHitTesting() {
        let five = GridGeometry(rows: 5), four = GridGeometry(rows: 4)
        XCTAssertEqual(five.size.height, five.headerHeight + 5 * five.cellHeight)
        XCTAssertEqual(four.columnRect(column: 0).height, four.size.height)
        let r = five.cellRect(index: 35) // first cell of a sixth row
        XCTAssertNil(five.index(at: CGPoint(x: r.midX, y: r.midY)))
        XCTAssertEqual(five.index(at: CGPoint(x: r.midX, y: r.midY - five.cellHeight)), 28)
    }
}

final class FixedGridHeightTests: XCTestCase {
    /// The geometry the app builds for a month (always 6 rows).
    private func appGeometry(weekNumbers: Bool) -> GridGeometry {
        GridGeometry(showsWeekNumbers: weekNumbers, rows: MonthGrid.rows)
    }

    func testSizeIsTheSameForFourFiveAndSixWeekMonths() {
        // Feb 2026 covers 4 weeks, Nov 2026 5 and Aug 2026 6 with a Sunday
        // start (5, 6 and 6 with Monday). The geometry doesn't depend on the
        // month, and every month's days fit inside it.
        for weekNumbers in [false, true] {
            let g = appGeometry(weekNumbers: weekNumbers)
            XCTAssertEqual(g.rows, 6)
            XCTAssertEqual(g.size, CGSize(width: weekNumbers ? 255 : 231, height: 194))
            for fw in [1, 2] {
                for m in [2, 11, 8] {
                    let grid = MonthGrid(month: MonthKey(year: 2026, month: m), firstWeekday: fw)
                    for i in 0..<42 where grid.isInMonth(index: i) {
                        XCTAssertTrue(CGRect(origin: .zero, size: g.size).contains(g.cellRect(index: i)), "2026-\(m) fw\(fw) #\(i)")
                    }
                }
            }
        }
    }

    func testColumnShadingSpansAllSixRows() {
        let g = appGeometry(weekNumbers: true)
        for col in 0..<7 {
            XCTAssertEqual(g.columnRect(column: col).height, g.size.height)
            XCTAssertEqual(g.columnRect(column: col).maxY, g.cellRect(index: 35 + col).maxY)
        }
    }

    func testEmptyTrailingRowHitTestsToBlankCells() {
        // Feb 2026 (Sunday start): rows 5 and 6 are laid out but hold no days.
        let grid = MonthGrid(month: MonthKey(year: 2026, month: 2), firstWeekday: 1)
        let g = appGeometry(weekNumbers: false)
        for i in 28..<42 {
            let r = g.cellRect(index: i)
            XCTAssertEqual(g.index(at: CGPoint(x: r.midX, y: r.midY)), i)
            XCTAssertNil(grid.visibleDay(at: i))
        }
    }

    func testKeyboardMovesNeverLandOnABlankCell() {
        // The selection is always a day of the shown month (the month follows
        // the selection), so it always maps to an in-month cell.
        for fw in [1, 2] {
            var day = DayKey(year: 2025, month: 12, day: 1)
            for _ in 0..<500 {
                for n in [1, -1, 7, -7] {
                    let next = day.adding(days: n)
                    let g = MonthGrid(month: next.monthKey, firstWeekday: fw)
                    let i = try! XCTUnwrap(g.index(of: next))
                    XCTAssertTrue(g.isInMonth(index: i))
                }
                for n in [1, -1, 12, -12] {
                    let next = GridNavigation.day(day, movedByMonths: n)
                    let g = MonthGrid(month: next.monthKey, firstWeekday: fw)
                    XCTAssertTrue(g.isInMonth(index: try! XCTUnwrap(g.index(of: next))))
                }
                day = day.adding(days: 1)
            }
        }
    }
}

final class GridNavigationTests: XCTestCase {
    func testItsycalKeyMap() {
        XCTAssertEqual(GridNavigation.command(for: .left, modifiers: []), .moveMonths(-1))
        XCTAssertEqual(GridNavigation.command(for: .down, modifiers: []), .moveMonths(12))
        XCTAssertEqual(GridNavigation.command(for: .right, modifiers: .shift), .moveDays(1))
        XCTAssertEqual(GridNavigation.command(for: .up, modifiers: .shift), .moveDays(-7))
        XCTAssertEqual(GridNavigation.command(for: .character("j"), modifiers: []), .moveDays(7))
        XCTAssertEqual(GridNavigation.command(for: .returnKey, modifiers: []), .newEvent)
        XCTAssertEqual(GridNavigation.command(for: .escape, modifiers: []), .close)
        XCTAssertEqual(GridNavigation.command(for: .character(","), modifiers: .command), .openSettings)
        XCTAssertEqual(GridNavigation.command(for: .space, modifiers: []), .today)
        XCTAssertNil(GridNavigation.command(for: .character("z"), modifiers: []))
        XCTAssertNil(GridNavigation.command(for: .left, modifiers: .command))
    }

    func testMonthMoveClampsDay() {
        XCTAssertEqual(GridNavigation.day(DayKey(year: 2027, month: 1, day: 31), movedByMonths: 1),
                       DayKey(year: 2027, month: 2, day: 28))
        XCTAssertEqual(GridNavigation.day(DayKey(year: 2027, month: 3, day: 15), movedByMonths: -12),
                       DayKey(year: 2026, month: 3, day: 15))
    }
}

final class AgendaTests: XCTestCase {
    let cal = gregorian()
    let locale = Locale(identifier: "en_US_POSIX")

    func testRowsShowFirstDayAndOnlyBusyLaterDays() {
        let d = DayKey(year: 2026, month: 11, day: 9)
        let e = event("review", date(2026, 11, 11, 9), date(2026, 11, 11, 10))
        let rows = Agenda.rows(eventsByDay: [d.adding(days: 2): [e]], start: d, days: 7)
        XCTAssertEqual(rows, [.day(d), .noEvents(d), .day(d.adding(days: 2)), .event(e, day: d.adding(days: 2))])
        let all = Agenda.rows(eventsByDay: [:], start: d, days: 2, showEmptyDays: true)
        XCTAssertEqual(all.count, 4)
    }

    func testTimeText() {
        let d = DayKey(year: 2026, month: 11, day: 9)
        func text(_ e: EventSnapshot, _ day: DayKey = DayKey(year: 2026, month: 11, day: 9)) -> String {
            // Formatters use a narrow no-break space before AM/PM.
            Agenda.timeText(for: e, on: day, calendar: cal, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        XCTAssertEqual(text(event("a", date(2026, 11, 9, 9), date(2026, 11, 9, 10, 30))), "9:00 AM – 10:30 AM")
        XCTAssertEqual(text(event("b", date(2026, 11, 9), date(2026, 11, 10), allDay: true)), "All day")
        let overnight = event("c", date(2026, 11, 9, 22), date(2026, 11, 10, 2))
        XCTAssertEqual(text(overnight), "From 10:00 PM")
        XCTAssertEqual(text(overnight, d.adding(days: 1)), "Until 2:00 AM")
        let long = event("d", date(2026, 11, 8, 9), date(2026, 11, 11, 9))
        XCTAssertEqual(text(long, d), "All day")
    }
}
