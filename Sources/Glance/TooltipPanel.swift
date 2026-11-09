import AppKit
import GlanceCore

/// A small themed panel listing a day's events, shown on grid hover.
@MainActor
final class TooltipPanel: NSPanel {
    private let content = TooltipView()
    private var showTimer: Timer?
    private var pending: (lines: [TooltipView.Line], title: String, rect: CGRect, appearance: NSAppearance?, colors: ThemeColors)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        contentView = content
    }

    /// Show after a short hover delay; replaces any pending tooltip.
    func schedule(lines: [TooltipView.Line], title: String, near screenRect: CGRect, appearance: NSAppearance?, colors: ThemeColors) {
        cancel()
        guard !lines.isEmpty else { return }
        pending = (lines, title, screenRect, appearance, colors)
        showTimer = Timer.scheduledTimer(withTimeInterval: isVisible ? 0.05 : 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.pending else { return }
                self.present(lines: p.lines, title: p.title, near: p.rect, appearance: p.appearance, colors: p.colors)
            }
        }
    }

    func cancel() {
        showTimer?.invalidate()
        showTimer = nil
        pending = nil
        orderOut(nil)
    }

    private func present(lines: [TooltipView.Line], title: String, near rect: CGRect, appearance: NSAppearance?, colors: ThemeColors) {
        self.appearance = appearance
        content.colors = colors
        content.title = title
        content.lines = lines
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 4)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
            if origin.y < vf.minY + 4 { origin.y = rect.maxY + 4 }
        }
        setFrame(CGRect(origin: origin, size: size), display: true)
        orderFront(nil)
    }
}

@MainActor
final class TooltipView: NSView {
    struct Line {
        var time: String
        var title: String
        var color: NSColor
    }

    var lines: [Line] = [] { didSet { needsDisplay = true } }
    var title = "" { didSet { needsDisplay = true } }
    var colors: ThemeColors?

    private let padding: CGFloat = 8
    private let lineHeight: CGFloat = 17
    private let maxWidth: CGFloat = 280
    private var titleFont: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
    private var font: NSFont { .systemFont(ofSize: 11) }
    private var timeFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }

    override var isFlipped: Bool { true }

    private var timeColumnWidth: CGFloat {
        lines.map { ($0.time as NSString).size(withAttributes: [.font: timeFont]).width }.max().map { $0.rounded(.up) + 8 } ?? 0
    }

    override var fittingSize: NSSize {
        let titleW = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let rowW = lines.map { 12 + timeColumnWidth + ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let w = min(maxWidth, max(titleW, rowW).rounded(.up) + 2 * padding)
        return NSSize(width: max(w, 120), height: 2 * padding + lineHeight * CGFloat(lines.count + 1))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let colors else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        colors.background.setFill()
        path.fill()
        colors.divider.setStroke()
        path.lineWidth = 1
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5).stroke()

        var y = padding
        let width = bounds.width - 2 * padding
        draw(title, at: CGPoint(x: padding, y: y), width: width, font: titleFont, color: colors.primaryText)
        y += lineHeight
        let tw = timeColumnWidth
        for line in lines {
            line.color.setFill()
            NSBezierPath(ovalIn: CGRect(x: padding, y: y + 5, width: 6, height: 6)).fill()
            draw(line.time, at: CGPoint(x: padding + 12, y: y), width: tw, font: timeFont, color: colors.secondaryText)
            draw(line.title, at: CGPoint(x: padding + 12 + tw, y: y), width: width - 12 - tw, font: font, color: colors.primaryText)
            y += lineHeight
        }
    }

    private func draw(_ s: String, at p: CGPoint, width: CGFloat, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(with: CGRect(x: p.x, y: p.y, width: max(width, 1), height: lineHeight),
                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                             attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
}
