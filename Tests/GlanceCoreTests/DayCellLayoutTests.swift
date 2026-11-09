import CoreText
import XCTest
@testable import GlanceCore

final class DayCellLayoutTests: XCTestCase {
    /// The grid's 13pt system font, measured the way NSString sizes a line.
    private var metrics: DayCellLayout.FontMetrics {
        let f = CTFontCreateUIFontForLanguage(.system, 13, nil)!
        let ascent = CTFontGetAscent(f), descent = CTFontGetDescent(f), leading = CTFontGetLeading(f)
        return .init(lineHeight: ascent + descent + leading, ascender: ascent, capHeight: CTFontGetCapHeight(f))
    }

    private var cells: [CGRect] {
        let g = GridGeometry()
        return [g.cellRect(index: 0), g.cellRect(index: 15), g.cellRect(index: 41)]
    }

    func testDotsSitInsideTheRingWithRoomToSpare() {
        for cell in cells {
            let l = DayCellLayout(cell: cell, font: metrics)
            for n in 1...3 {
                for dot in l.dotRects(count: n) {
                    XCTAssertGreaterThanOrEqual(l.ringInner.maxY - dot.maxY, 2, "below, \(n) dots")
                    XCTAssertGreaterThanOrEqual(dot.minX - l.ringInner.minX, 2, "left, \(n) dots")
                    XCTAssertGreaterThanOrEqual(l.ringInner.maxX - dot.maxX, 2, "right, \(n) dots")
                    XCTAssertTrue(l.pill.contains(dot))
                }
            }
        }
    }

    func testDotsClearTheDigitsAndBalanceTheGaps() {
        for cell in cells {
            let l = DayCellLayout(cell: cell, font: metrics)
            let dot = l.dotRects(count: 1)[0]
            let above = dot.minY - l.baseline, below = l.ringInner.maxY - dot.maxY
            XCTAssertGreaterThanOrEqual(above, 2, "gap to the digits")
            XCTAssertLessThan(l.digitTop, l.baseline)
            XCTAssertLessThanOrEqual(abs(above - below), 0.5, "above \(above) below \(below)")
            XCTAssertGreaterThanOrEqual(l.digitTop, l.ringInner.minY, "digits inside the ring")
        }
    }

    func testDotRowIsCentredAndCapped() {
        let l = DayCellLayout(cell: GridGeometry().cellRect(index: 0), font: metrics)
        XCTAssertEqual(l.dotRects(count: 0), [])
        XCTAssertEqual(l.dotRects(count: 7).count, 3)
        for n in 1...3 {
            let r = l.dotRects(count: n)
            XCTAssertLessThanOrEqual(abs((r.first!.minX + r.last!.maxX) / 2 - l.cell.midX), 0.5)
            XCTAssertEqual(r.first!.minY, r.first!.minY.rounded(), "whole-point y")
        }
    }
}
