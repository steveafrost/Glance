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

final class AgendaSizingTests: XCTestCase {
    private func grid(_ m: Int, _ fw: Int) -> MonthGrid { MonthGrid(month: MonthKey(year: 2026, month: m), firstWeekday: fw) }
    /// The geometry the app builds for a month: only its own weeks.
    private func geometry(_ g: MonthGrid, weekNumbers: Bool) -> GridGeometry {
        GridGeometry(showsWeekNumbers: weekNumbers, rows: g.visibleRows)
    }

    func testGridPlusFullAgendaIsTheSameEveryMonth() {
        // Feb 2026 covers 4 weeks, Nov 5 and Aug 6 with a Sunday start
        // (5, 6 and 6 with Monday).
        let full6 = GridGeometry(rows: 6)
        let total = full6.size.height + AgendaSizing.baseMaxHeight // 194 + 420
        XCTAssertEqual(total, 614)
        for (m, fw, rows) in [(2, 1, 4), (11, 1, 5), (8, 1, 6), (2, 2, 5), (11, 2, 6), (8, 2, 6)] {
            for weekNumbers in [false, true] {
                let g = geometry(grid(m, fw), weekNumbers: weekNumbers)
                XCTAssertEqual(g.rows, rows, "2026-\(m) fw\(fw)")
                XCTAssertEqual(g.size.height, g.headerHeight + CGFloat(rows) * g.cellHeight)
                XCTAssertEqual(g.size.height + AgendaSizing.maxHeight(for: g), total, "2026-\(m) fw\(fw) wk\(weekNumbers)")
                // A long agenda fills exactly that.
                let agenda = AgendaSizing.height(content: 2000, minimum: 26, geometry: g)
                XCTAssertEqual(g.size.height + agenda, total)
            }
        }
        XCTAssertEqual(AgendaSizing.maxHeight(for: geometry(grid(2, 1), weekNumbers: false)), 420 + 2 * 29)
    }

    func testShortAgendaKeepsItsOwnHeight() {
        let g = geometry(grid(2, 1), weekNumbers: false)
        XCTAssertEqual(AgendaSizing.height(content: 100, minimum: 26, geometry: g), 100)
        XCTAssertEqual(AgendaSizing.height(content: 0, minimum: 26, geometry: g), 26, "empty agenda still shows a row")
    }

    func testScreenClampWinsWhenSmaller() {
        for m in [2, 11, 8] {
            let g = geometry(grid(m, 1), weekNumbers: true)
            XCTAssertEqual(AgendaSizing.height(content: 2000, minimum: 26, geometry: g, screenRoom: 300), 300)
            XCTAssertEqual(AgendaSizing.height(content: 2000, minimum: 26, geometry: g, screenRoom: 10),
                           AgendaSizing.minimumScreenRoom, "never squeezed below the floor")
            // Plenty of room: the month's own maximum applies.
            XCTAssertEqual(AgendaSizing.height(content: 2000, minimum: 26, geometry: g, screenRoom: 5000),
                           AgendaSizing.maxHeight(for: g))
            // Short content under a roomy screen is unaffected.
            XCTAssertEqual(AgendaSizing.height(content: 100, minimum: 26, geometry: g, screenRoom: 300), 100)
        }
    }

    func testColumnShadingCoversOnlyTheMonthsRows() {
        let feb = geometry(grid(2, 1), weekNumbers: true)
        for col in 0..<7 {
            XCTAssertEqual(feb.columnRect(column: col).maxY, feb.cellRect(index: 21 + col).maxY)
            XCTAssertEqual(feb.columnRect(column: col).height, feb.size.height)
        }
        // A cell below the month's last week isn't hit-testable.
        let r = feb.cellRect(index: 28)
        XCTAssertNil(feb.index(at: CGPoint(x: r.midX, y: r.midY)))
    }

    func testKeyboardMovesNeverLandOnABlankCell() {
        // The selection is always a day of the shown month (the month follows
        // the selection), so it maps to a drawn cell inside the shown rows.
        for fw in [1, 2] {
            var day = DayKey(year: 2025, month: 12, day: 1)
            for _ in 0..<500 {
                let targets = [1, -1, 7, -7].map { day.adding(days: $0) }
                    + [1, -1, 12, -12].map { GridNavigation.day(day, movedByMonths: $0) }
                for next in targets {
                    let g = MonthGrid(month: next.monthKey, firstWeekday: fw)
                    let i = try! XCTUnwrap(g.index(of: next))
                    XCTAssertTrue(g.isInMonth(index: i))
                    XCTAssertLessThan(i / 7, g.visibleRows)
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
