import AppKit
import GlanceCore

/// The month grid, drawn by one layer-backed view: no per-cell views, so a
/// month change is a single redraw with no layout work.
@MainActor
final class MonthGridView: NSView {
    struct Model {
        var grid: MonthGrid
        var selected: DayKey
        var today: DayKey
        var highlighted: WeekdaySet
        var dots: [DayKey: [NSColor]]
        var geometry: GridGeometry
    }

    var model: Model { didSet { needsDisplay = true } }
    var colors: ThemeColors? { didSet { needsDisplay = true } }

    var onSelect: ((DayKey) -> Void)?
    var onDoubleClick: ((DayKey) -> Void)?
    var onHover: ((DayKey?, CGRect) -> Void)?
    var onCommand: ((GridCommand) -> Void)?

    private var hovered: Int? {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    init(model: Model) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: model.geometry.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Calendar")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { model.geometry.size }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let colors else { return }
        let g = model.geometry, grid = model.grid
        let radius: CGFloat = 6

        // Highlighted weekday columns.
        colors.highlightedWeekdayBackground.setFill()
        for col in 0..<MonthGrid.columns where model.highlighted.contains(weekday: grid.weekday(forColumn: col)) {
            NSBezierPath(roundedRect: g.columnRect(column: col).insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).fill()
        }

        // Weekday header.
        let symbols = Calendar.autoupdatingCurrent.veryShortStandaloneWeekdaySymbols
        let headerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        for col in 0..<MonthGrid.columns {
            let wd = grid.weekday(forColumn: col)
            drawCentered(symbols[wd - 1], in: g.headerRect(column: col), font: headerFont,
                         color: model.highlighted.contains(weekday: wd) ? colors.secondaryText : colors.primaryText)
        }

        // Week numbers.
        if g.showsWeekNumbers {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            for (row, n) in grid.weekNumbers().enumerated() {
                if let r = g.weekNumberRect(row: row) {
                    drawCentered(String(n), in: r, font: font, color: colors.weekNumberText)
                }
            }
        }

        let dayFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let todayFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        for (i, day) in grid.days.enumerated() {
            let cell = g.cellRect(index: i)
            guard cell.intersects(dirtyRect) else { continue }
            let pill = cell.insetBy(dx: 2, dy: 2)
            let isToday = day == model.today
            if isToday {
                colors.today.setFill()
                NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            } else if i == hovered {
                colors.hover.setFill()
                NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            }
            if day == model.selected {
                let ring = NSBezierPath(roundedRect: pill.insetBy(dx: 0.75, dy: 0.75), xRadius: radius - 0.75, yRadius: radius - 0.75)
                ring.lineWidth = 1.5
                (isToday ? colors.onToday : colors.selection).setStroke()
                ring.stroke()
            }
            let textColor = isToday ? colors.onToday : (grid.isInMonth(day) ? colors.primaryText : colors.otherMonthText)
            var textRect = cell
            textRect.origin.y -= 2
            drawCentered(String(day.day), in: textRect, font: isToday ? todayFont : dayFont, color: textColor)

            if let dots = model.dots[day], !dots.isEmpty {
                drawDots(dots, in: cell, override: isToday ? colors.onToday : nil)
            }
        }
    }

    private func drawDots(_ dots: [NSColor], in cell: CGRect, override: NSColor?) {
        let d: CGFloat = 4, spacing: CGFloat = 2
        let shown = Array(dots.prefix(3))
        let total = CGFloat(shown.count) * d + CGFloat(shown.count - 1) * spacing
        var x = (cell.midX - total / 2).rounded()
        let y = cell.maxY - 7
        for c in shown {
            (override ?? c).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: d, height: d)).fill()
            x += d + spacing
        }
    }

    private func drawCentered(_ s: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded())
        (s as NSString).draw(at: p, withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        onHover?(nil, .zero)
    }

    private func updateHover(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = model.geometry.index(at: p)
        guard i != hovered else { return }
        hovered = i
        if let i {
            onHover?(model.grid.days[i], convert(model.geometry.cellRect(index: i), to: nil))
        } else {
            onHover?(nil, .zero)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        guard let i = model.geometry.index(at: p) else { return }
        let day = model.grid.days[i]
        if event.clickCount == 2 { onDoubleClick?(day) } else { onSelect?(day) }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let key = Self.gridKey(event), let cmd = GridNavigation.command(for: key, modifiers: Self.modifiers(event)) else {
            super.keyDown(with: event)
            return
        }
        onCommand?(cmd)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self,
              let key = Self.gridKey(event), Self.modifiers(event).contains(.command),
              let cmd = GridNavigation.command(for: key, modifiers: Self.modifiers(event)) else {
            return super.performKeyEquivalent(with: event)
        }
        onCommand?(cmd)
        return true
    }

    static func modifiers(_ e: NSEvent) -> GridModifiers {
        var m: GridModifiers = []
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.command) { m.insert(.command) }
        if f.contains(.option) { m.insert(.option) }
        if f.contains(.control) { m.insert(.control) }
        return m
    }

    static func gridKey(_ e: NSEvent) -> GridKey? {
        switch e.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 36, 76: return .returnKey
        case 53: return .escape
        case 49: return .space
        default:
            guard let c = e.charactersIgnoringModifiers, c.count == 1, let ch = c.first else { return nil }
            return .character(ch)
        }
    }
}
