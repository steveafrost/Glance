import AppKit
import CoreText
import GlanceCore

/// Draws the menu bar template image from an `IconLayout`.
@MainActor
enum IconRenderer {
    static let fontSize: CGFloat = 11.5

    static func font(for style: IconLayout.Style) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: style == .filled ? .bold : .semibold)
    }

    static func metrics(for text: String, style: IconLayout.Style) -> IconLayout.TextMetrics {
        let line = ctLine(text, font: font(for: style))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Digits sit on the baseline and reach cap height; centre on that.
        return IconLayout.TextMetrics(width: CGFloat(width), capHeight: font(for: style).capHeight)
    }

    private static func ctLine(_ text: String, font: NSFont) -> CTLine {
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        return CTLineCreateWithAttributedString(attr)
    }

    static func image(text: String?, style: IconLayout.Style, meeting: Bool,
                      placement: IconLayout.Placement, opticalOffset: CGFloat) -> NSImage {
        var m = IconLayout.Metrics()
        m.opticalOffset = opticalOffset
        let layout = IconLayout(text: text.map { metrics(for: $0, style: style) }, showsMeeting: meeting,
                                placement: placement, metrics: m)
        let font = font(for: style)
        let image = NSImage(size: layout.canvasSize, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            if let r = layout.meetingRect { drawMeetingGlyph(in: r) }
            guard let box = layout.boxRect, let text, let origin = layout.textOrigin else { return true }
            let outer = CGPath(roundedRect: box, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil)
            let line = ctLine(text, font: font)
            switch style {
            case .filled:
                ctx.addPath(outer)
                ctx.fillPath()
                // Knock the digits out of the box.
                ctx.setBlendMode(.destinationOut)
                ctx.textPosition = origin
                CTLineDraw(line, ctx)
                ctx.setBlendMode(.normal)
            case .outline:
                let w = layout.outlineWidth
                let innerRect = box.insetBy(dx: w, dy: w)
                let r = max(layout.cornerRadius - w, 0)
                let ring = CGMutablePath()
                ring.addPath(outer)
                ring.addPath(CGPath(roundedRect: innerRect, cornerWidth: r, cornerHeight: r, transform: nil))
                ctx.addPath(ring)
                ctx.fillPath(using: .evenOdd)
                ctx.textPosition = origin
                CTLineDraw(line, ctx)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawMeetingGlyph(in rect: CGRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Meeting")?
            .withSymbolConfiguration(config) else { return }
        // Fit the symbol's aspect inside rect, centred.
        let s = symbol.size
        let scale = min(rect.width / s.width, rect.height / s.height)
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        let r = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        symbol.draw(in: r)
    }
}
