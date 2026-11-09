import XCTest
@testable import GlanceCore

final class SettingsModelTests: XCTestCase {
    typealias M = SettingsModel

    func testIconChoiceMapsOntoStyleAndHideIcon() {
        XCTAssertEqual(M.IconChoice(style: .outline, hidden: false), .outline)
        XCTAssertEqual(M.IconChoice(style: .filled, hidden: false), .filled)
        XCTAssertEqual(M.IconChoice(style: .filled, hidden: true), .none)
        XCTAssertTrue(M.IconChoice.none.hidesIcon)
        XCTAssertEqual(M.IconChoice.none.style(keeping: .filled), .filled, "None keeps the style for later")
        XCTAssertEqual(M.IconChoice.outline.style(keeping: .filled), .outline)
    }

    func testEmptyItemWarning() {
        XCTAssertTrue(M.showsEmptyItemWarning(icon: .none, clockPattern: ""))
        XCTAssertTrue(M.showsEmptyItemWarning(icon: .none, clockPattern: "  "))
        XCTAssertFalse(M.showsEmptyItemWarning(icon: .none, clockPattern: "h:mm a"))
        XCTAssertFalse(M.showsEmptyItemWarning(icon: .outline, clockPattern: ""))
    }

    func testClockPresets() {
        XCTAssertEqual(M.ClockPreset.matching(""), .none)
        XCTAssertEqual(M.ClockPreset.matching("h:mm a"), .time)
        XCTAssertEqual(M.ClockPreset.matching("EEE h:mm a"), .dayTime)
        XCTAssertEqual(M.ClockPreset.matching("EEE d MMM h:mm a"), .dayDateTime)
        XCTAssertEqual(M.ClockPreset.matching("HH:mm:ss"), .custom)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let df = DateFormatter()
        df.calendar = cal
        df.timeZone = cal.timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        let sample = M.ClockPreset.sampleDate(calendar: cal)
        func f(_ p: String) -> String { df.dateFormat = p; return df.string(from: sample) }
        XCTAssertEqual(M.ClockPreset.time.title(format: f), "1:00 PM")
        XCTAssertEqual(M.ClockPreset.dayTime.title(format: f), "Mon 1:00 PM")
        XCTAssertEqual(M.ClockPreset.dayDateTime.title(format: f), "Mon 9 Nov 1:00 PM")
        XCTAssertEqual(M.ClockPreset.custom.title(format: f), "Custom…")
    }

    func testStepperValues() {
        XCTAssertEqual(M.minutes(5), "5 min")
        XCTAssertEqual(M.days(1), "1 day")
        XCTAssertEqual(M.days(7), "7 days")
    }

    func testWeekdayChipOrder() {
        XCTAssertEqual(M.orderedWeekdays(firstWeekday: 1), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(M.orderedWeekdays(firstWeekday: 2), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(M.orderedWeekdays(firstWeekday: 7), [7, 1, 2, 3, 4, 5, 6])
    }

    func testShowAllHideAllPerAccount() {
        let all: Set = ["a1", "a2", "b1"]
        let hidden = M.setAll(["a1", "a2"], on: false, selected: all, allIDs: all)
        XCTAssertEqual(hidden.selected, ["b1"])
        XCTAssertEqual(hidden.stored, ["b1"])
        XCTAssertFalse(M.allShown(["a1", "a2"], selected: hidden.selected))
        let shown = M.setAll(["a1", "a2"], on: true, selected: hidden.selected, allIDs: all)
        XCTAssertEqual(shown.selected, all)
        XCTAssertNil(shown.stored, "everything selected stores the default")
        XCTAssertTrue(M.allShown(["a1", "a2"], selected: shown.selected))
    }

    func testTabHeightScrollsOnlyWhenTooTall() {
        XCTAssertEqual(M.contentHeight(natural: 420.3, available: 900).height, 421)
        XCTAssertFalse(M.contentHeight(natural: 420, available: 900).scrolls)
        let tall = M.contentHeight(natural: 1200, available: 800)
        XCTAssertEqual(tall.height, 800)
        XCTAssertTrue(tall.scrolls)
    }

    func testThemeModeRoundTripsAndRingsTheVisibleFlavor() {
        for c in ThemeChoice.allCases { XCTAssertEqual(M.ThemeMode(c).choice, c) }
        XCTAssertEqual(M.ThemeMode(.catppuccinAuto).ringedFlavor(isDarkMode: true), .mocha)
        XCTAssertEqual(M.ThemeMode(.catppuccinAuto).ringedFlavor(isDarkMode: false), .latte)
        XCTAssertEqual(M.ThemeMode(.frappe).ringedFlavor(isDarkMode: false), .frappe)
        XCTAssertNil(M.ThemeMode(.system).ringedFlavor(isDarkMode: true))
    }
}
