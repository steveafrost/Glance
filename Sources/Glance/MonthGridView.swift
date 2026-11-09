import AppKit
import GlanceCore
import os

private let swipeLog = Logger(subsystem: "com.steveafrost.Glance", category: "swipe")

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
    var onCommand: ((GridCommand) -> Void)?
    private var swipe = SwipeTracker()

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

        // One device-pixel grid for snapping: 2 on Retina and in 2x renders.
        let scale = NSGraphicsContext.current.map { abs($0.cgContext.userSpaceToDeviceSpaceTransform.a) }
            ?? window?.backingScaleFactor ?? 1
        // Only the month's own days; out-of-month slots stay empty.
        for (i, day) in grid.days.enumerated() where grid.isInMonth(index: i) {
            let cell = g.cellRect(index: i)
            guard cell.intersects(dirtyRect) else { continue }
            let layout = DayCellLayout(cell: cell, font: Self.dayMetrics, scale: scale)
            let isToday = day == model.today
            if isToday {
                colors.today.setFill()
                NSBezierPath(roundedRect: layout.pill, xRadius: radius, yRadius: radius).fill()
            } else if i == hovered {
                colors.hover.setFill()
                NSBezierPath(roundedRect: layout.pill, xRadius: radius, yRadius: radius).fill()
            }
            if day == model.selected {
                let inset = DayCellLayout.ringWidth / 2
                let ring = NSBezierPath(roundedRect: layout.ringPath, xRadius: radius - inset, yRadius: radius - inset)
                ring.lineWidth = DayCellLayout.ringWidth
                (isToday ? colors.onToday : colors.selection).setStroke()
                ring.stroke()
            }
            let text = String(day.day), font = isToday ? Self.todayFont : Self.dayFont
            (text as NSString).draw(at: layout.textOrigin(ink: Self.ink(text, bold: isToday)),
                                    withAttributes: [.font: font, .foregroundColor: isToday ? colors.onToday : colors.primaryText])

            if let dots = model.dots[day], !dots.isEmpty {
                for (rect, c) in zip(layout.dotRects(count: dots.count), dots) {
                    (isToday ? colors.onToday : c).setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
        }
    }

    static let dayFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let todayFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let dayMetrics: DayCellLayout.FontMetrics = {
        let size = ("0" as NSString).size(withAttributes: [.font: dayFont])
        return .init(lineHeight: size.height, ascender: dayFont.ascender, capHeight: dayFont.capHeight)
    }()

    /// Ink bounds of each day number, measured once: 31 strings in 2 weights.
    private static var inkCache: [String: CGRect] = [:]
    private static func ink(_ s: String, bold: Bool) -> CGRect {
        let key = bold ? "b" + s : s
        if let r = inkCache[key] { return r }
        let r = DigitInk.bounds(of: s, font: bold ? todayFont : dayFont)
        inkCache[key] = r
        return r
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

    override func mouseExited(with event: NSEvent) { hovered = nil }

    private func updateHover(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = model.geometry.index(at: p).flatMap { model.grid.isInMonth(index: $0) ? $0 : nil }
        if i != hovered { hovered = i }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        guard let i = model.geometry.index(at: p), let day = model.grid.visibleDay(at: i) else { return }
        if event.clickCount == 2 { onDoubleClick?(day) } else { onSelect?(day) }
    }

    // MARK: Trackpad swipe

    /// Horizontal two-finger swipe over the grid changes month (once per gesture).
    override func scrollWheel(with event: NSEvent) {
        let outcome = swipe.handle(.init(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            phase: Self.phase(event.phase), isMomentum: event.momentumPhase != [],
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            invertedFromDevice: event.isDirectionInvertedFromDevice))
        switch outcome {
        case .changeMonth(let n):
            swipeLog.notice("swipe month \(n) natural=\(event.isDirectionInvertedFromDevice)")
            onCommand?(.moveMonths(n))
        case .consumed: break
        case .passThrough: super.scrollWheel(with: event)
        }
    }

    private static func phase(_ p: NSEvent.Phase) -> SwipeTracker.Phase {
        if p.contains(.began) || p.contains(.mayBegin) { return .began }
        if p.contains(.changed) || p.contains(.stationary) { return .changed }
        if p.contains(.ended) { return .ended }
        if p.contains(.cancelled) { return .cancelled }
        return .none
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
