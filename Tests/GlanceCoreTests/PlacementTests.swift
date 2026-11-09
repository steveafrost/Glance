import XCTest
@testable import GlanceCore

final class PlacementTests: XCTestCase {
    // Main display 3440x1440 with a 30pt menu bar; a second display to its left.
    let main = PopoverPlacement.Screen(frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1410))
    let left = PopoverPlacement.Screen(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                       visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1050))
    let size = CGSize(width: 260, height: 500)

    func item(x: CGFloat, top: CGFloat = 1440, width: CGFloat = 40) -> CGRect {
        CGRect(x: x, y: top - 30, width: width, height: 30)
    }

    func testCentresUnderItem() {
        let r = PopoverPlacement.place(.init(itemFrame: item(x: 2000), itemVisible: true, screens: [main],
                                             windowSize: size, initialPresentation: true))!
        XCTAssertEqual(r.origin, CGPoint(x: 1890, y: 1410 - 2 - 500))
        XCTAssertEqual(r.arrowX, 130)
        XCTAssertFalse(r.usesFallback)
    }

    func testClampsToRightEdgeAndDropsArrowNearCorner() {
        let r = PopoverPlacement.place(.init(itemFrame: item(x: 3420, width: 20), itemVisible: true, screens: [main],
                                             windowSize: size, initialPresentation: true))!
        XCTAssertEqual(r.origin.x, 3440 - 260 - 10)
        XCTAssertNil(r.arrowX, "arrow would overlap the rounded corner")
        let r2 = PopoverPlacement.place(.init(itemFrame: item(x: 3300), itemVisible: true, screens: [main],
                                              windowSize: size, initialPresentation: true))!
        XCTAssertEqual(r2.origin.x, 3170)
        XCTAssertEqual(r2.arrowX, 150)
    }

    func testPicksDisplayThatOwnsTheItem() {
        let r = PopoverPlacement.place(.init(itemFrame: item(x: -500, top: 1080), itemVisible: true,
                                             screens: [main, left], windowSize: size, initialPresentation: true))!
        XCTAssertEqual(r.screenFrame, left.frame)
        XCTAssertEqual(r.origin.y, 1050 - 2 - 500)
    }

    func testAutoHiddenMenuBarParksItemAboveScreenButStillAnchors() {
        // Item sits just above the top of the screen and reads as not visible.
        let parked = CGRect(x: 2000, y: 1440, width: 40, height: 30)
        let r = PopoverPlacement.place(.init(itemFrame: parked, itemVisible: false, screens: [main],
                                             windowSize: size, initialPresentation: true))!
        XCTAssertFalse(r.usesFallback)
        XCTAssertEqual(r.origin.x, 1890)
        XCTAssertEqual(r.origin.y, 1440 - 2 - 500, "clamped to the screen top")
    }

    func testOccludedItemFallsBackToTopRight() {
        let r = PopoverPlacement.place(.init(itemFrame: item(x: 1000), itemVisible: false, screens: [main],
                                             windowSize: size, initialPresentation: true))!
        XCTAssertTrue(r.usesFallback)
        XCTAssertEqual(r.origin.x, 3440 - 260 - 10)
        XCTAssertEqual(r.origin.y, 1410 - 2 - 500)
        XCTAssertNil(r.arrowX)
    }

    func testFallbackSticksWhileOpen() {
        let first = PopoverPlacement.place(.init(itemFrame: item(x: 1000), itemVisible: false, screens: [main],
                                                 windowSize: size, initialPresentation: true))!
        let again = PopoverPlacement.place(.init(itemFrame: item(x: 1000), itemVisible: true, screens: [main],
                                                 windowSize: size, initialPresentation: false, previous: first))!
        XCTAssertEqual(again.origin, first.origin)
        XCTAssertTrue(again.usesFallback)
    }

    func testOffscreenItemUsesMainScreen() {
        let r = PopoverPlacement.place(.init(itemFrame: CGRect(x: 99999, y: 99999, width: 1, height: 1), itemVisible: false,
                                             screens: [left, main], mainScreenIndex: 1, windowSize: size,
                                             initialPresentation: true))!
        XCTAssertEqual(r.screenFrame, main.frame)
        XCTAssertTrue(r.usesFallback)
    }

    func testHeightCappedToScreen() {
        let tall = CGSize(width: 260, height: 5000)
        let r = PopoverPlacement.place(.init(itemFrame: item(x: 2000), itemVisible: true, screens: [main],
                                             windowSize: tall, initialPresentation: true))!
        XCTAssertEqual(r.maxHeight, 1410 - 2 - 10)
        XCTAssertEqual(r.origin.y, 10)
    }
}
