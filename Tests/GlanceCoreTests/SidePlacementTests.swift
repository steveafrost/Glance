import XCTest
@testable import GlanceCore

final class SidePlacementTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 3440, height: 1410)
    let calendar = CGRect(x: 3137, y: 736, width: 263, height: 673)
    let size = CGSize(width: 360, height: 400)

    func testSitsLeftWithApexTouchingTheCalendarAtTheRow() {
        let r = SidePlacement.place(size: size, anchorY: 1200, calendarFrame: calendar, visibleFrame: visible)
        XCTAssertEqual(r.arrowEdge, .right)
        XCTAssertEqual(r.frame.maxX, calendar.minX - SidePlacement.gap)
        XCTAssertEqual(r.frame.minY + r.arrowPosition, 1200)
    }

    func testFlipsRightWhenNoRoomOnTheLeft() {
        let cal = CGRect(x: 200, y: 736, width: 263, height: 673)
        let r = SidePlacement.place(size: size, anchorY: 1200, calendarFrame: cal, visibleFrame: visible)
        XCTAssertEqual(r.arrowEdge, .left)
        XCTAssertEqual(r.frame.minX, cal.maxX + SidePlacement.gap)
    }

    func testStaysOnScreenAndClampsArrowAwayFromCorners() {
        let r = SidePlacement.place(size: size, anchorY: 1405, calendarFrame: calendar, visibleFrame: visible)
        XCTAssertEqual(r.frame.maxY, visible.maxY - SidePlacement.margin)
        XCTAssertEqual(r.arrowPosition, size.height - 16 - PopoverShape.arrowHalfWidth)
        let low = SidePlacement.place(size: size, anchorY: 3, calendarFrame: calendar, visibleFrame: visible)
        XCTAssertEqual(low.frame.minY, SidePlacement.margin)
        XCTAssertEqual(low.arrowPosition, 16 + PopoverShape.arrowHalfWidth)
    }
}
