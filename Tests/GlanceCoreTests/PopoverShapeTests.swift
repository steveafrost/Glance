import XCTest
@testable import GlanceCore

final class PopoverShapeTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 263, height: 400)

    /// macOS 27: the 33pt item at x 3252 draws its 17pt box 8pt in, so the
    /// box centre (3268.5) is the target, not some other point on the button.
    func testApexPointsAtDrawnBoxCentre() {
        let screen = PopoverPlacement.Screen(frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                             visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1410))
        let button = CGRect(x: 3252, y: 1411, width: 33, height: 30)
        for boxCentre in [3268.5, 3290.5, 3262.0] as [CGFloat] {
            var b = button
            b.size.width = 60 // e.g. a meeting glyph or clock beside the box
            let r = PopoverPlacement.place(.init(itemFrame: b, itemVisible: true, screens: [screen],
                                                 windowSize: CGSize(width: 263, height: 400),
                                                 initialPresentation: true, arrowTargetX: boxCentre))!
            let arrow = PopoverShape.Arrow(edge: .top, position: r.arrowX!)
            let apex = PopoverShape.apex(in: bounds, arrow: arrow, cornerRadius: 16)!
            XCTAssertEqual(r.origin.x + apex.x, boxCentre, accuracy: 0.5)
            XCTAssertEqual(apex.y, bounds.maxY, "the apex is the window's top edge")
            XCTAssertEqual(r.origin.x, r.origin.x.rounded(), "window stays on whole points")
        }
    }

    func testPathTopIsTheApex() {
        let arrow = PopoverShape.Arrow(edge: .top, position: 131.5)
        let path = PopoverShape.path(in: bounds, arrow: arrow, cornerRadius: 16)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, bounds.maxY, accuracy: 0.01)
        XCTAssertTrue(path.contains(CGPoint(x: 131.5, y: bounds.maxY - 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 131.5 - 12, y: bounds.maxY - 1)), "flanks taper to the base")
    }

    /// The old path was a rounded rect plus a separate arrow subpath that
    /// overlapped by 1pt with opposite winding, which punched a line across
    /// the arrow's base. One contour has no hole there.
    func testNoSeamAcrossArrowBase() {
        let arrow = PopoverShape.Arrow(edge: .top, position: 131.5)
        let path = PopoverShape.path(in: bounds, arrow: arrow, cornerRadius: 16)
        let baseY = bounds.maxY - arrow.height
        for dy in stride(from: -1.5, through: 1.5, by: 0.25) {
            for dx in [-6, 0, 6] as [CGFloat] {
                let p = CGPoint(x: 131.5 + dx, y: baseY + CGFloat(dy))
                XCTAssertTrue(path.contains(p), "hole at \(p)")
                XCTAssertTrue(path.contains(p, using: .evenOdd), "even-odd hole at \(p)")
            }
        }
    }

    func testProportionsMatchNativeArrow() {
        XCTAssertEqual(PopoverShape.arrowHeight, 10)
        XCTAssertEqual(PopoverShape.arrowHalfWidth * 2, 26)
    }

    func testSideArrows() {
        for edge in [PopoverShape.Edge.left, .right] {
            let arrow = PopoverShape.Arrow(edge: edge, position: 200)
            let path = PopoverShape.path(in: bounds, arrow: arrow, cornerRadius: 16)
            let apex = PopoverShape.apex(in: bounds, arrow: arrow, cornerRadius: 16)!
            XCTAssertEqual(apex.x, edge == .left ? bounds.minX : bounds.maxX)
            XCTAssertEqual(apex.y, 200)
            let inside = CGPoint(x: edge == .left ? bounds.minX + 1 : bounds.maxX - 1, y: 200)
            XCTAssertTrue(path.contains(inside))
            XCTAssertTrue(path.contains(CGPoint(x: bounds.midX, y: 200)))
            let body = PopoverShape.bodyRect(in: bounds, arrowEdge: edge)
            XCTAssertEqual(body.width, bounds.width - 10)
        }
    }

    func testArrowDroppedWhenItWouldHitACorner() {
        let arrow = PopoverShape.Arrow(edge: .top, position: 20)
        XCTAssertNil(PopoverShape.apex(in: bounds, arrow: arrow, cornerRadius: 16))
        let path = PopoverShape.path(in: bounds, arrow: arrow, cornerRadius: 16)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, bounds.maxY - 10, accuracy: 0.01)
    }
}
