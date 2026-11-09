import XCTest
@testable import GlanceCore

final class EventDraftTests: XCTestCase {
    let cal = gregorian()

    func testNewEventTodayStartsNextHour() {
        let d = EventDraft.new(on: DayKey(year: 2026, month: 11, day: 9), now: date(2026, 11, 9, 12, 9), calendar: cal, calendarID: "c")
        XCTAssertEqual(d.start, date(2026, 11, 9, 13))
        XCTAssertEqual(d.end, date(2026, 11, 9, 14))
        XCTAssertTrue(d.isNew)
    }

    func testNewEventOtherDayStartsAtNine() {
        let d = EventDraft.new(on: DayKey(year: 2026, month: 11, day: 12), now: date(2026, 11, 9, 12), calendar: cal, calendarID: "c")
        XCTAssertEqual(d.start, date(2026, 11, 12, 9))
    }

    func testNewEventLateTonightFallsBackToNine() {
        let d = EventDraft.new(on: DayKey(year: 2026, month: 11, day: 9), now: date(2026, 11, 9, 23, 30), calendar: cal, calendarID: "c")
        XCTAssertEqual(d.start, date(2026, 11, 9, 9))
    }

    func testValidation() {
        var d = EventDraft(start: date(2026, 11, 9, 10), end: date(2026, 11, 9, 9), calendarID: "c")
        XCTAssertEqual(d.validate(calendar: cal), .endBeforeStart)
        d.end = date(2026, 11, 9, 11)
        XCTAssertNil(d.validate(calendar: cal))
        d.urlText = "not a url"
        XCTAssertEqual(d.validate(calendar: cal), .invalidURL("not a url"))
        d.urlText = "https://example.com/x"
        XCTAssertNil(d.validate(calendar: cal))
        XCTAssertEqual(d.url?.host, "example.com")
        d.calendarID = nil
        XCTAssertEqual(d.validate(calendar: cal), .noCalendar)
        XCTAssertNotNil(EventDraft.ValidationError.endBeforeStart.errorDescription)
    }

    func testAllDayNormalisesToWholeDays() {
        var d = EventDraft(isAllDay: true, start: date(2026, 11, 9, 15), end: date(2026, 11, 10, 8), calendarID: "c")
        let n = d.normalizedDates(calendar: cal)
        XCTAssertEqual(n.start, date(2026, 11, 9))
        XCTAssertEqual(n.end, date(2026, 11, 11))
        // An all-day end before the start is clamped to one day, not an error.
        d.end = date(2026, 11, 8)
        XCTAssertNil(d.validate(calendar: cal))
        XCTAssertEqual(d.normalizedDates(calendar: cal).end, date(2026, 11, 10))
    }

    func testTitleDefaults() {
        XCTAssertEqual(EventDraft(title: "  ", start: Date(), end: Date(), calendarID: nil).trimmedTitle, "New Event")
        XCTAssertEqual(EventDraft(title: " Lunch ", start: Date(), end: Date(), calendarID: nil).trimmedTitle, "Lunch")
    }
}
