import XCTest
@testable import GlanceCore

final class SwipeTrackerTests: XCTestCase {
    /// Feed a gesture of `steps` equal raw deltas and collect month changes.
    private func run(_ t: inout SwipeTracker, rawX: CGFloat, rawY: CGFloat = 0, steps: Int = 10,
                     natural: Bool = true) -> [SwipeTracker.Outcome] {
        var out = [t.handle(.init(deltaX: 0, phase: .began, invertedFromDevice: natural))]
        for _ in 0..<steps {
            out.append(t.handle(.init(deltaX: rawX, deltaY: rawY, phase: .changed, invertedFromDevice: natural)))
        }
        out.append(t.handle(.init(deltaX: 0, phase: .ended, invertedFromDevice: natural)))
        return out
    }

    private func changes(_ o: [SwipeTracker.Outcome]) -> [Int] {
        o.compactMap { if case .changeMonth(let n) = $0 { n } else { nil } }
    }

    func testNaturalScrollingFingersLeftGoesForward() {
        var t = SwipeTracker()
        // Natural scrolling: raw delta has the fingers' sign; fingers left = negative.
        XCTAssertEqual(changes(run(&t, rawX: -10, natural: true)), [1])
        XCTAssertEqual(changes(run(&t, rawX: 10, natural: true)), [-1])
    }

    func testClassicScrollingFingersLeftGoesForward() {
        var t = SwipeTracker()
        // Without natural scrolling the raw sign is flipped: fingers left = positive.
        XCTAssertEqual(changes(run(&t, rawX: 10, natural: false)), [1])
        XCTAssertEqual(changes(run(&t, rawX: -10, natural: false)), [-1])
    }

    func testThreshold() {
        var t = SwipeTracker(threshold: 40)
        XCTAssertEqual(changes(run(&t, rawX: -13, steps: 3)), [], "39pt is below the threshold")
        let outcomes = run(&t, rawX: -10, steps: 4)
        XCTAssertEqual(outcomes[4], .changeMonth(1), "fires on reaching 40pt")
        XCTAssertEqual(outcomes[1], .consumed, "horizontal movement below the threshold is swallowed")
    }

    func testAtMostOneChangePerGesture() {
        var t = SwipeTracker()
        XCTAssertEqual(changes(run(&t, rawX: -30, steps: 20)), [1])
        // Reversing within the same gesture doesn't fire again either.
        var r = SwipeTracker()
        var out = [r.handle(.init(deltaX: 0, phase: .began))]
        out += (0..<5).map { _ in r.handle(.init(deltaX: -20, phase: .changed)) }
        out += (0..<10).map { _ in r.handle(.init(deltaX: 20, phase: .changed)) }
        XCTAssertEqual(changes(out), [1])
        // A new gesture can change again.
        XCTAssertEqual(changes(run(&t, rawX: -30)), [1])
    }

    func testMomentumIsIgnored() {
        var t = SwipeTracker()
        XCTAssertEqual(changes(run(&t, rawX: -30)), [1])
        let momentum = (0..<20).map { _ in t.handle(.init(deltaX: -50, phase: .none, isMomentum: true)) }
        XCTAssertEqual(changes(momentum), [])
        XCTAssertTrue(momentum.allSatisfy { $0 == .consumed })
        // Momentum with no swipe before it isn't ours.
        var fresh = SwipeTracker()
        XCTAssertEqual(fresh.handle(.init(deltaX: -50, phase: .none, isMomentum: true)), .passThrough)
    }

    func testVerticalDominantInputPassesThrough() {
        var t = SwipeTracker()
        let out = run(&t, rawX: -6, rawY: 12, steps: 20)
        XCTAssertEqual(changes(out), [])
        XCTAssertEqual(out[5], .passThrough)
        XCTAssertEqual(out.last, .passThrough)
    }

    func testMouseWheelPassesThrough() {
        var t = SwipeTracker()
        XCTAssertEqual(t.handle(.init(deltaX: -100, phase: .none, hasPreciseDeltas: false)), .passThrough)
        XCTAssertEqual(t.handle(.init(deltaX: -100, phase: .changed, hasPreciseDeltas: false)), .passThrough)
    }
}
