import CoreGraphics

/// Turns a horizontal two-finger trackpad swipe into at most one month
/// change per gesture.
///
/// Direction follows the fingers, not the content: with natural scrolling
/// (`invertedFromDevice == true`) `scrollingDeltaX` already has the fingers'
/// sign; without it the sign is flipped. Fingers moving left go forward a
/// month, right goes back.
public struct SwipeTracker: Sendable {
    public enum Phase: Sendable { case none, began, changed, ended, cancelled }

    public enum Outcome: Equatable, Sendable {
        /// Change month by this many (+1 forward, -1 back).
        case changeMonth(Int)
        /// Part of a horizontal swipe (or momentum after one); swallow it.
        case consumed
        /// Not a trackpad swipe we handle (mouse wheel, vertical scroll).
        case passThrough
    }

    public struct Event: Sendable {
        public var deltaX: CGFloat
        public var deltaY: CGFloat
        public var phase: Phase
        public var isMomentum: Bool
        public var hasPreciseDeltas: Bool
        public var invertedFromDevice: Bool

        public init(deltaX: CGFloat, deltaY: CGFloat = 0, phase: Phase, isMomentum: Bool = false,
                    hasPreciseDeltas: Bool = true, invertedFromDevice: Bool = true) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.phase = phase
            self.isMomentum = isMomentum
            self.hasPreciseDeltas = hasPreciseDeltas
            self.invertedFromDevice = invertedFromDevice
        }
    }

    public let threshold: CGFloat
    private var fingerX: CGFloat = 0
    private var totalY: CGFloat = 0
    private var tracking = false
    private var fired = false

    public init(threshold: CGFloat = 40) { self.threshold = threshold }

    public mutating func handle(_ e: Event) -> Outcome {
        guard e.hasPreciseDeltas else { return .passThrough }
        // Momentum continues after the fingers lift; one flick must not skip months.
        if e.isMomentum { return fired ? .consumed : .passThrough }

        switch e.phase {
        case .began:
            fingerX = 0
            totalY = 0
            tracking = true
            fired = false
        case .changed:
            if !tracking { tracking = true; fingerX = 0; totalY = 0; fired = false }
        case .ended, .cancelled:
            let wasHorizontal = fired || abs(fingerX) > abs(totalY)
            tracking = false
            fingerX = 0
            totalY = 0
            return wasHorizontal ? .consumed : .passThrough
        case .none:
            return .passThrough
        }

        fingerX += e.invertedFromDevice ? e.deltaX : -e.deltaX
        totalY += e.deltaY
        if fired { return .consumed }
        guard abs(fingerX) > abs(totalY) else { return .passThrough }
        if abs(fingerX) >= threshold {
            fired = true
            return .changeMonth(fingerX < 0 ? 1 : -1)
        }
        return .consumed
    }
}
