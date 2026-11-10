import CoreGraphics
import Foundation

/// Geometry for the menu bar date icon.
///
/// The status bar button centres a short image inside its own frame, and on
/// macOS 27's 30pt menu bar that frame isn't centred in the bar, which is why
/// a plain 16pt image lands one point high. Instead, the canvas is as tall
/// as the button and the box is placed in *bar* coordinates, so it sits
/// exactly where we want however the button is positioned.
///
/// Coordinates are AppKit's (origin bottom-left) for the canvas; bar
/// positions are measured from the top edge of the menu bar.
public struct IconLayout: Equatable, Sendable {
    public enum Style: String, Sendable, CaseIterable, Codable {
        case outline, filled
    }

    public struct TextMetrics: Equatable, Sendable {
        public var width: CGFloat
        public var capHeight: CGFloat
        public init(width: CGFloat, capHeight: CGFloat) {
            self.width = width
            self.capHeight = capHeight
        }
    }

    /// Where the status button sits within the menu bar.
    public struct Placement: Equatable, Sendable {
        /// Menu bar thickness (30 on macOS 27 notch-less displays).
        public var barHeight: CGFloat
        /// The button's height.
        public var buttonHeight: CGFloat
        /// Distance from the bar's top edge to the button's top edge.
        public var buttonTop: CGFloat
        /// Backing scale factor; positions round to device pixels.
        public var scale: CGFloat

        public init(barHeight: CGFloat, buttonHeight: CGFloat, buttonTop: CGFloat, scale: CGFloat = 1) {
            self.barHeight = barHeight
            self.buttonHeight = buttonHeight
            self.buttonTop = buttonTop
            self.scale = max(1, scale)
        }

        /// Assume the button fills the bar when we can't measure it.
        public static func fullBar(_ height: CGFloat, scale: CGFloat = 1) -> Placement {
            Placement(barHeight: height, buttonHeight: height, buttonTop: 0, scale: scale)
        }
    }

    public struct Metrics: Equatable, Sendable {
        public var boxHeight: CGFloat = 16
        public var minBoxWidth: CGFloat = 17
        public var horizontalPadding: CGFloat = 4
        public var cornerRadius: CGFloat = 4
        public var outlineWidth: CGFloat = 1.5
        /// Shift (points, + = down) from the bar's geometric centre.
        public var opticalOffset: CGFloat = 0
        public init() {}
    }

    public let canvasSize: CGSize
    /// Nil when the icon has no date box.
    public let boxRect: CGRect?
    public let textOrigin: CGPoint?
    public let cornerRadius: CGFloat
    public let outlineWidth: CGFloat

    public init(text: TextMetrics?, placement: Placement, metrics: Metrics = Metrics()) {
        let s = placement.scale
        func px(_ v: CGFloat) -> CGFloat { (v * s).rounded() / s }

        let canvasHeight = max(placement.buttonHeight, 1)
        // Desired vertical centre in bar coordinates, converted to canvas
        // coordinates (bottom-left origin).
        let centreFromBarTop = placement.barHeight / 2 + metrics.opticalOffset
        let centreFromButtonTop = centreFromBarTop - placement.buttonTop
        func originY(height h: CGFloat) -> CGFloat {
            // Top edge from button top, snapped to pixels, then flipped.
            let top = px(centreFromButtonTop - h / 2)
            let y = canvasHeight - top - h
            return min(max(y, 0), max(canvasHeight - h, 0))
        }

        var x: CGFloat = 0

        if let text {
            let width = max(metrics.minBoxWidth, (text.width + 2 * metrics.horizontalPadding).rounded(.up))
            let box = CGRect(x: x, y: originY(height: metrics.boxHeight), width: width, height: metrics.boxHeight)
            boxRect = box
            // Centre cap height in the box: digits have no descenders, so
            // the baseline sits (box - capHeight) / 2 above the bottom.
            textOrigin = CGPoint(x: px(box.minX + (box.width - text.width) / 2),
                                 y: px(box.minY + (box.height - text.capHeight) / 2))
            x = box.maxX
        } else {
            boxRect = nil
            textOrigin = nil
        }
        canvasSize = CGSize(width: max(x, 1), height: canvasHeight)
        cornerRadius = metrics.cornerRadius
        outlineWidth = metrics.outlineWidth
    }

    /// Rows (0 = top of the bar, inclusive) the box covers at the given scale.
    public func boxRows(placement: Placement) -> ClosedRange<Int>? {
        guard let box = boxRect else { return nil }
        let topInBar = placement.buttonTop + (canvasSize.height - box.maxY)
        let first = Int((topInBar * placement.scale).rounded())
        let count = Int((box.height * placement.scale).rounded())
        return first...(first + count - 1)
    }
}
