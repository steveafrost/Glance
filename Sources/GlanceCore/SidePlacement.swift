import CoreGraphics

/// Places a panel beside the calendar window with its arrow pointing at a
/// day cell or agenda row: to the left by default, to the right when the
/// left side has no room, kept inside the screen's visible frame.
public enum SidePlacement {
    public static let gap: CGFloat = 2
    public static let margin: CGFloat = 10

    public struct Result: Equatable, Sendable {
        public var frame: CGRect
        /// The panel edge carrying the arrow (`.right` when it sits on the left).
        public var arrowEdge: PopoverShape.Edge
        /// Arrow apex along that edge, in panel coordinates (y).
        public var arrowPosition: CGFloat
    }

    /// - Parameters:
    ///   - anchorY: screen y of the row the panel belongs to.
    ///   - calendarFrame: the calendar window frame (its body spans the full width).
    public static func place(size: CGSize, anchorY: CGFloat, calendarFrame: CGRect, visibleFrame: CGRect,
                             cornerRadius: CGFloat = 16, arrow: PopoverShape.Arrow = .init(edge: .right, position: 0)) -> Result {
        let leftX = calendarFrame.minX - gap - size.width
        let fitsLeft = leftX >= visibleFrame.minX + margin
        let x = fitsLeft ? leftX : min(calendarFrame.maxX + gap, visibleFrame.maxX - margin - size.width)
        var y = (anchorY - size.height / 2).rounded()
        y = min(y, visibleFrame.maxY - margin - size.height)
        y = max(y, visibleFrame.minY + margin)
        let lo = cornerRadius + arrow.halfWidth, hi = size.height - cornerRadius - arrow.halfWidth
        let position = min(max(anchorY - y, lo), max(lo, hi))
        return Result(frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
                      arrowEdge: fitsLeft ? .right : .left, arrowPosition: position)
    }
}
