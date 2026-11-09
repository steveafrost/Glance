import CoreGraphics

/// The outline of a popover-style window: a rounded body and an arrow,
/// traced as one closed contour so fill, mask, border and shadow all see a
/// single shape (no seam at the arrow's base, no winding cancellation).
///
/// Proportions follow a native NSPopover arrow: about 10pt deep on a 26pt
/// base, with a rounded apex and flanks that leave the body tangentially.
/// Coordinates are AppKit's (origin bottom-left).
public enum PopoverShape {
    public enum Edge: Sendable, Equatable { case top, left, right }

    public struct Arrow: Sendable, Equatable {
        public var edge: Edge
        /// Apex position along the edge: x for `.top`, y for `.left`/`.right`.
        public var position: CGFloat
        public var height: CGFloat
        public var halfWidth: CGFloat
        public init(edge: Edge, position: CGFloat, height: CGFloat = PopoverShape.arrowHeight,
                    halfWidth: CGFloat = PopoverShape.arrowHalfWidth) {
            self.edge = edge
            self.position = position
            self.height = height
            self.halfWidth = halfWidth
        }
    }

    public static let arrowHeight: CGFloat = 10
    public static let arrowHalfWidth: CGFloat = 13

    /// The body: `bounds` minus the arrow's depth on its edge.
    public static func bodyRect(in bounds: CGRect, arrowEdge: Edge?, arrowHeight h: CGFloat = arrowHeight) -> CGRect {
        switch arrowEdge {
        case .top: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height - h)
        case .left: CGRect(x: bounds.minX + h, y: bounds.minY, width: bounds.width - h, height: bounds.height)
        case .right: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - h, height: bounds.height)
        case nil: bounds
        }
    }

    /// Whether an arrow at `position` fits between the edge's rounded corners.
    public static func fits(_ arrow: Arrow, body: CGRect, cornerRadius r: CGFloat) -> Bool {
        let (lo, hi): (CGFloat, CGFloat) = arrow.edge == .top ? (body.minX, body.maxX) : (body.minY, body.maxY)
        return arrow.position - arrow.halfWidth >= lo + r && arrow.position + arrow.halfWidth <= hi - r
    }

    /// The arrow's tip, or nil when there is no arrow or it doesn't fit.
    public static func apex(in bounds: CGRect, arrow: Arrow?, cornerRadius r: CGFloat) -> CGPoint? {
        guard let arrow else { return nil }
        let body = bodyRect(in: bounds, arrowEdge: arrow.edge, arrowHeight: arrow.height)
        guard fits(arrow, body: body, cornerRadius: r) else { return nil }
        switch arrow.edge {
        case .top: return CGPoint(x: arrow.position, y: body.maxY + arrow.height)
        case .left: return CGPoint(x: body.minX - arrow.height, y: arrow.position)
        case .right: return CGPoint(x: body.maxX + arrow.height, y: arrow.position)
        }
    }

    public static func path(in bounds: CGRect, arrow: Arrow?, cornerRadius: CGFloat) -> CGPath {
        let body = bodyRect(in: bounds, arrowEdge: arrow?.edge, arrowHeight: arrow?.height ?? 0)
        let r = min(cornerRadius, body.width / 2, body.height / 2)
        let drawn = arrow.flatMap { fits($0, body: body, cornerRadius: r) ? $0 : nil }

        let tl = CGPoint(x: body.minX, y: body.maxY), tr = CGPoint(x: body.maxX, y: body.maxY)
        let br = CGPoint(x: body.maxX, y: body.minY), bl = CGPoint(x: body.minX, y: body.minY)
        // Clockwise on screen: up the left side, right along the top, down
        // the right side, left along the bottom.
        let sides: [(from: CGPoint, to: CGPoint, next: CGPoint, normal: CGVector, edge: Edge?)] = [
            (bl, tl, tr, CGVector(dx: -1, dy: 0), .left),
            (tl, tr, br, CGVector(dx: 0, dy: 1), .top),
            (tr, br, bl, CGVector(dx: 1, dy: 0), .right),
            (br, bl, tl, CGVector(dx: 0, dy: -1), nil),
        ]

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bl.x, y: bl.y + r))
        for side in sides {
            if let a = drawn, a.edge == side.edge {
                addArrow(a, to: path, from: side.from, to: side.to, normal: side.normal)
            }
            path.addArc(tangent1End: side.to, tangent2End: side.next, radius: r)
        }
        path.closeSubpath()
        return path
    }

    private static func addArrow(_ a: Arrow, to path: CGMutablePath, from start: CGPoint, to end: CGPoint, normal n: CGVector) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let d = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        // Distance along this side from its start to the apex.
        let t: CGFloat = switch a.edge {
        case .top: a.position - start.x
        case .left: a.position - start.y
        case .right: start.y - a.position
        }
        func at(_ along: CGFloat, out: CGFloat = 0) -> CGPoint {
            CGPoint(x: start.x + d.dx * along + n.dx * out, y: start.y + d.dy * along + n.dy * out)
        }
        let w = a.halfWidth, h = a.height
        path.addLine(to: at(t - w))
        // Flanks leave the body tangentially and meet in a rounded tip.
        path.addCurve(to: at(t, out: h), control1: at(t - w * 0.5), control2: at(t - w * 0.28, out: h))
        path.addCurve(to: at(t + w), control1: at(t + w * 0.28, out: h), control2: at(t + w * 0.5))
    }
}
