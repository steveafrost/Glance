import CoreGraphics
import CoreText
import Foundation

/// Where a day cell's pill, selection ring, digits and event dots go.
/// Each dot row sits midway between the digits' baseline and the ring's
/// inner edge, so the gaps above and below match and can't drift apart.
/// Horizontally the digits' ink and the dot row share one centre,
/// `centerX`, snapped once to a device pixel; nothing rounds separately.
public struct DayCellLayout: Equatable, Sendable {
    /// Vertical metrics of the day-number font.
    public struct FontMetrics: Equatable, Sendable {
        public var lineHeight: CGFloat
        public var ascender: CGFloat
        public var capHeight: CGFloat
        public init(lineHeight: CGFloat, ascender: CGFloat, capHeight: CGFloat) {
            self.lineHeight = lineHeight
            self.ascender = ascender
            self.capHeight = capHeight
        }
    }

    public static let pillInset: CGFloat = 2
    public static let ringWidth: CGFloat = 1.5
    public static let dotSize: CGFloat = 4
    public static let dotSpacing: CGFloat = 2
    public static let maxDots = 3
    /// The digits centre in the top band of this height, not the whole cell,
    /// leaving the space below for the dots.
    public static let textBandHeight: CGFloat = 24

    public let cell: CGRect
    public let font: FontMetrics
    /// Device pixels per point (the backing scale), for pixel snapping.
    public let scale: CGFloat

    public init(cell: CGRect, font: FontMetrics, scale: CGFloat = 1) {
        self.cell = cell
        self.font = font
        self.scale = max(scale, 1)
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

    /// The cell's single horizontal centre, on a whole device pixel.
    public var centerX: CGFloat { snap(cell.midX) }

    /// Where to draw the day number (its pen origin and line-box top) so its
    /// ink, not its advance box, centres on `centerX`. `ink` is the glyph
    /// bounds relative to the pen origin (see `DigitInk.bounds`). The x
    /// stays fractional; text is positioned at subpixel precision.
    public func textOrigin(ink: CGRect) -> CGPoint { CGPoint(x: centerX - ink.midX, y: textTop) }

    /// The today / hover fill.
    public var pill: CGRect { cell.insetBy(dx: Self.pillInset, dy: Self.pillInset) }
    /// The path the selection ring strokes (centre of the stroke).
    public var ringPath: CGRect { pill.insetBy(dx: Self.ringWidth / 2, dy: Self.ringWidth / 2) }
    /// Inside edge of the selection ring.
    public var ringInner: CGRect { pill.insetBy(dx: Self.ringWidth, dy: Self.ringWidth) }

    /// Top of the day number's line box (flipped coordinates).
    public var textTop: CGFloat { (cell.minY + Self.textBandHeight / 2 - font.lineHeight / 2).rounded() }
    public var baseline: CGFloat { textTop + font.ascender }
    /// Vertical extent of the digit glyphs (cap height above the baseline).
    public var digitTop: CGFloat { baseline - font.capHeight }

    /// Top of the dot row: centred in the space between baseline and ring,
    /// on a whole point so the dots stay crisp at 1x.
    public var dotTop: CGFloat { (baseline + (ringInner.maxY - baseline - Self.dotSize) / 2).rounded() }

    public func dotRects(count: Int) -> [CGRect] {
        let n = min(max(count, 0), Self.maxDots)
        guard n > 0 else { return [] }
        let total = CGFloat(n) * Self.dotSize + CGFloat(n - 1) * Self.dotSpacing
        // total is even, so with centerX on a pixel every dot is too.
        let x0 = centerX - total / 2
        return (0..<n).map {
            CGRect(x: x0 + CGFloat($0) * (Self.dotSize + Self.dotSpacing), y: dotTop, width: Self.dotSize, height: Self.dotSize)
        }
    }
}

/// Glyph ink of a short string, measured with CoreText.
public enum DigitInk {
    /// The string's glyph bounds relative to its pen origin: x from the
    /// origin, y up from the baseline. Path bounds, so no context is needed.
    public static func bounds(of string: String, font: CTFont) -> CGRect {
        let attributed = NSAttributedString(string: string, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attributed), .useGlyphPathBounds)
    }
}
