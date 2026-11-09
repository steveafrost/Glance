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

    // MARK: Horizontal centring

    /// The grid's monospaced-digit 13pt system font, in a given weight.
    private func digitFont(bold: Bool) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, 13, nil)!
        let desc = CTFontDescriptorCreateCopyWithFeature(CTFontCopyFontDescriptor(base),
                                                         kNumberSpacingType as CFNumber, kMonospacedNumbersSelector as CFNumber)
        return CTFontCreateWithFontDescriptor(desc, 13, nil)
    }

    private let samples = ["1", "7", "11", "20", "31"]

    func testDotsCentreOnTheDigitsInk() {
        for width: CGFloat in [33, 32] { // odd and even cell widths
            for scale: CGFloat in [1, 2] {
                for origin: CGFloat in [0, 24, 57] {
                    let cell = CGRect(x: origin + width, y: 20, width: width, height: 29)
                    let l = DayCellLayout(cell: cell, font: metrics, scale: scale)
                    for bold in [false, true] {
                        for s in samples {
                            let ink = DigitInk.bounds(of: s, font: digitFont(bold: bold))
                            let inkCentre = l.textOrigin(ink: ink).x + ink.midX
                            for n in 1...3 {
                                let dots = l.dotRects(count: n)
                                let dotCentre = (dots.first!.minX + dots.last!.maxX) / 2
                                XCTAssertLessThanOrEqual(abs(dotCentre - inkCentre), 0.25,
                                                         "\(s) bold \(bold), \(n) dots, width \(width) @\(scale)x")
                            }
                        }
                    }
                }
            }
        }
    }

    func testSharedCentreAndDotsLandOnDevicePixels() {
        for width: CGFloat in [33, 32] {
            for scale: CGFloat in [1, 2, 3] {
                let cell = CGRect(x: 24 + width * 3, y: 0, width: width, height: 29)
                let l = DayCellLayout(cell: cell, font: metrics, scale: scale)
                XCTAssertEqual(l.centerX * scale, (l.centerX * scale).rounded())
                XCTAssertLessThanOrEqual(abs(l.centerX - cell.midX), 0.5 / scale)
                for n in 1...3 {
                    for d in l.dotRects(count: n) {
                        XCTAssertEqual(d.minX * scale, (d.minX * scale).rounded(), "\(n) dots @\(scale)x")
                    }
                }
            }
        }
    }

    func testInkIsNotTheAdvanceBox() {
        // Why the ink is measured: "1" sits well off-centre in its advance box,
        // so centring the advance width would leave the dots visibly off.
        let f = digitFont(bold: false)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "1", attributes: [kCTFontAttributeName as NSAttributedString.Key: f]))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ink = DigitInk.bounds(of: "1", font: f)
        XCTAssertGreaterThan(ink.width, 0)
        XCTAssertGreaterThan(abs(advance / 2 - ink.midX), 0.25, "advance \(advance) ink \(ink)")
    }
}
