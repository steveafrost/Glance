import XCTest
@testable import GlanceCore

final class MonthCacheTests: XCTestCase {
    let nov = MonthKey(year: 2026, month: 11), dec = MonthKey(year: 2026, month: 12), oct = MonthKey(year: 2026, month: 10)

    func testFetchesOnlyMissingMonthsAndSkipsInFlight() {
        var cache = MonthCache<[String]>()
        XCTAssertEqual(cache.missing(for: [oct, nov, dec]), [oct, nov, dec])
        let g = cache.begin([oct, nov])
        XCTAssertEqual(cache.missing(for: [oct, nov, dec]), [dec])
        cache.store(["a"], for: nov, generation: g)
        XCTAssertTrue(cache.isFresh(nov))
        XCTAssertEqual(cache.value(for: nov), ["a"])
        XCTAssertEqual(cache.missing(for: [nov, dec]), [dec])
    }

    func testInvalidateKeepsStaleValuesButRefetches() {
        var cache = MonthCache<[String]>()
        let g = cache.begin([nov])
        cache.store(["old"], for: nov, generation: g)
        cache.invalidate()
        XCTAssertEqual(cache.value(for: nov), ["old"], "stale values stay visible")
        XCTAssertFalse(cache.isFresh(nov))
        XCTAssertEqual(cache.missing(for: [nov]), [nov])
    }

    func testResultsFromOlderGenerationAreDropped() {
        var cache = MonthCache<[String]>()
        let g0 = cache.begin([nov])
        cache.invalidate()
        let g1 = cache.begin([nov])
        XCTAssertFalse(cache.store(["slow, pre-change"], for: nov, generation: g0))
        XCTAssertNil(cache.value(for: nov))
        XCTAssertTrue(cache.store(["fresh"], for: nov, generation: g1))
        XCTAssertEqual(cache.value(for: nov), ["fresh"])
    }

    func testEvictsLeastRecentlyUsed() {
        var cache = MonthCache<Int>(capacity: 2)
        let g = cache.begin([oct, nov, dec])
        cache.store(1, for: oct, generation: g)
        cache.store(2, for: nov, generation: g)
        cache.touch([oct])
        cache.store(3, for: dec, generation: g)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.value(for: oct))
        XCTAssertNil(cache.value(for: nov))
        XCTAssertNotNil(cache.value(for: dec))
    }

    func testVisibleRangeIncludesGridAndAgenda() {
        let grid = MonthGrid(month: nov, firstWeekday: 1) // Nov 1 – Dec 12
        let r = VisibleRange(grid: grid, selected: DayKey(year: 2026, month: 12, day: 10), agendaDays: 7)
        XCTAssertEqual(r.first, DayKey(year: 2026, month: 11, day: 1))
        XCTAssertEqual(r.last, DayKey(year: 2026, month: 12, day: 16))
        XCTAssertEqual(r.months, [nov, dec])
        let mon = VisibleRange(grid: MonthGrid(month: nov, firstWeekday: 2), selected: DayKey(year: 2026, month: 11, day: 9), agendaDays: 1)
        XCTAssertEqual(mon.months, [oct, nov, dec])
    }
}

final class EventBucketingTests: XCTestCase {
    let cal = gregorian()

    func testAllDayFirstThenByStart() {
        let day = DayKey(year: 2026, month: 11, day: 9)
        let late = event("late", date(2026, 11, 9, 15), date(2026, 11, 9, 16))
        let early = event("early", date(2026, 11, 9, 9), date(2026, 11, 9, 10))
        let allDay = event("holiday", date(2026, 11, 9), date(2026, 11, 10), allDay: true)
        let spanning = event("trip", date(2026, 11, 8, 18), date(2026, 11, 11, 9))
        let buckets = EventBucketing.bucket([late, early, allDay, spanning], calendar: cal, range: day...day.adding(days: 3))
        XCTAssertEqual(buckets[day]?.map(\.title), ["holiday", "trip", "early", "late"])
        XCTAssertEqual(buckets[day.adding(days: 2)]?.map(\.title), ["trip"])
        XCTAssertNil(buckets[day.adding(days: 3)])
        XCTAssertNil(buckets[day.adding(days: -1)], "clipped to range")
    }

    func testCalendarGroupingSortsSourcesAndCalendars() {
        let cals = [
            CalendarInfo(id: "1", title: "Work", sourceTitle: "iCloud", color: RGBA(hex: 0), allowsModifications: true),
            CalendarInfo(id: "2", title: "Home", sourceTitle: "iCloud", color: RGBA(hex: 0), allowsModifications: true),
            CalendarInfo(id: "3", title: "Team", sourceTitle: "Google", color: RGBA(hex: 0), allowsModifications: true),
        ]
        let groups = CalendarGrouping.group(cals)
        XCTAssertEqual(groups.map(\.title), ["Google", "iCloud"])
        XCTAssertEqual(groups[1].calendars.map(\.title), ["Home", "Work"])
    }
}
