import XCTest
@testable import GlanceCore

final class ClockFormatTests: XCTestCase {
    func testDetectsTimeAndSeconds() {
        XCTAssertEqual(ClockFormat("h:mm a").usesTime, true)
        XCTAssertEqual(ClockFormat("h:mm a").usesSeconds, false)
        XCTAssertEqual(ClockFormat("HH:mm:ss").usesSeconds, true)
        XCTAssertEqual(ClockFormat("EEE d MMM").usesTime, false)
        XCTAssertTrue(ClockFormat("   ").isEmpty)
    }

    func testIgnoresQuotedLetters() {
        let f = ClockFormat("EEE 'at' d 'secs'")
        XCTAssertFalse(f.usesTime)
        XCTAssertFalse(f.usesSeconds)
        // '' is a literal quote and must not open a quoted section.
        let g = ClockFormat("d''MMM h:mm")
        XCTAssertTrue(g.usesTime)
    }

    func testNextTickAlignsToMinute() {
        let cal = gregorian()
        let now = date(2026, 11, 9, 12, 9, 41)
        XCTAssertEqual(ClockFormat("h:mm").nextTick(after: now, calendar: cal), date(2026, 11, 9, 12, 10, 0))
        XCTAssertEqual(ClockFormat("h:mm").nextTick(after: date(2026, 11, 9, 12, 10, 0), calendar: cal),
                       date(2026, 11, 9, 12, 11, 0))
    }

    func testNextTickAlignsToSecond() {
        let cal = gregorian()
        let now = date(2026, 11, 9, 12, 9, 41).addingTimeInterval(0.3)
        XCTAssertEqual(ClockFormat("h:mm:ss").nextTick(after: now, calendar: cal), date(2026, 11, 9, 12, 9, 42))
    }

    func testDateOnlyFormatTicksAtMidnight() {
        let cal = gregorian()
        XCTAssertEqual(ClockFormat("EEE d").nextTick(after: date(2026, 11, 9, 23, 59), calendar: cal),
                       date(2026, 11, 10))
    }

    func testSampleDatesCoverEveryMonthWeekdayAndPeriod() {
        let cal = gregorian()
        let dates = ClockFormat.sampleDates(calendar: cal)
        let weekdays = Set(dates.map { cal.component(.weekday, from: $0) })
        let months = Set(dates.map { cal.component(.month, from: $0) })
        let hours = Set(dates.map { cal.component(.hour, from: $0) })
        XCTAssertEqual(weekdays.count, 7)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(hours, [10, 22])
    }

    func testWidthProbe() {
        XCTAssertEqual(ClockFormat.widthProbe(for: "Mon 9 12:41"), "Mon 0 00:00")
    }
}
