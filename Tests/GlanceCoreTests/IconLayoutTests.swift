import XCTest
@testable import GlanceCore

final class IconLayoutTests: XCTestCase {
    let digits = IconLayout.TextMetrics(width: 7, capHeight: 8.2)

    func testSixteenPointBoxIsCentredOnThirtyPointBar() {
        // Whatever the button's position, the box covers rows 7–22 of a 30pt bar.
        // (30, -1) is what macOS 27 reports: a 30pt button poking 1pt above the screen.
        for (height, top) in [(CGFloat(30), CGFloat(0)), (30, -1), (22, 4), (24, 3), (22, 3)] {
            let p = IconLayout.Placement(barHeight: 30, buttonHeight: height, buttonTop: top)
            let layout = IconLayout(text: digits, placement: p)
            XCTAssertEqual(layout.boxRows(placement: p), 7...22, "button \(height)@\(top)")
            XCTAssertEqual(layout.canvasSize.height, height)
        }
    }

    func testLegacyTwentyFourPointBar() {
        let p = IconLayout.Placement.fullBar(24)
        let layout = IconLayout(text: digits, placement: p)
        XCTAssertEqual(layout.boxRows(placement: p), 4...19)
    }

    func testOpticalOffsetMovesBoxDown() {
        var m = IconLayout.Metrics()
        m.opticalOffset = 1
        let p = IconLayout.Placement(barHeight: 30, buttonHeight: 22, buttonTop: 4)
        XCTAssertEqual(IconLayout(text: digits, placement: p, metrics: m).boxRows(placement: p), 8...23)
    }

    func testRetinaSnapsToHalfPoints() {
        var m = IconLayout.Metrics()
        m.boxHeight = 15
        let p = IconLayout.Placement(barHeight: 24, buttonHeight: 24, buttonTop: 0, scale: 2)
        let layout = IconLayout(text: digits, placement: p, metrics: m)
        // (24 - 15) / 2 = 4.5pt from the top = 9 device rows.
        XCTAssertEqual(layout.boxRows(placement: p), 9...38)
        let one = IconLayout(text: digits, placement: .fullBar(24), metrics: m)
        // At 1x, 4.5 rounds to a whole pixel.
        XCTAssertEqual(one.boxRect!.minY.truncatingRemainder(dividingBy: 1), 0)
    }

    func testBoxWidthHasMinimumAndGrowsWithText() {
        let p = IconLayout.Placement.fullBar(30)
        XCTAssertEqual(IconLayout(text: digits, placement: p).boxRect?.width, 17)
        let wide = IconLayout(text: .init(width: 30.2, capHeight: 8.2), placement: p)
        XCTAssertEqual(wide.boxRect?.width, 39)
        XCTAssertEqual(wide.canvasSize.width, 39)
    }

    func testTextIsCentredInBox() {
        let p = IconLayout.Placement(barHeight: 30, buttonHeight: 22, buttonTop: 4)
        let layout = IconLayout(text: digits, placement: p)
        let box = layout.boxRect!, origin = layout.textOrigin!
        XCTAssertEqual(origin.x, box.minX + 5) // (17 - 7) / 2
        // Baseline sits (16 - 8.2) / 2 = 3.9 → 4 above the box bottom.
        XCTAssertEqual(origin.y - box.minY, 4)
    }



    func testBoxStaysInsideShortButton() {
        let p = IconLayout.Placement(barHeight: 30, buttonHeight: 14, buttonTop: 0)
        let layout = IconLayout(text: digits, placement: p)
        XCTAssertGreaterThanOrEqual(layout.boxRect!.minY, 0)
    }
}
