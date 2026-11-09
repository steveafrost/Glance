import AppKit
import GlanceCore

/// QA only (`--qa-keys dump-grid`): publishes the grid's cell layout and
/// offscreen 1x/2x renders on a private named pasteboard, so
/// `script/measure-grid.sh` can measure digit and dot alignment in pixels.
/// The sandbox hides the app's container from the shell; a named
/// pasteboard is reachable and leaves the general clipboard alone.
extension MonthGridView {
    static let qaPasteboard = NSPasteboard.Name("com.steveafrost.Glance.qa")

    func publishQADump(background: NSColor) {
        guard let window else { return }
        let m = model, winHeight = window.frame.height
        var cells: [[String: Any]] = []
        for (i, day) in m.grid.days.enumerated() where m.grid.isInMonth(index: i) {
            let r = m.geometry.cellRect(index: i)
            let w = convert(r, to: nil) // window coordinates, bottom-left origin
            let l = DayCellLayout(cell: CGRect(origin: .zero, size: r.size), font: Self.dayMetrics)
            cells.append([
                "day": day.day, "index": i, "today": day == m.today, "selected": day == m.selected,
                "dots": m.dots[day]?.count ?? 0,
                "grid": [r.minX, r.minY, r.width, r.height],
                "window": [w.minX, winHeight - w.maxY, w.width, w.height],
                "digitTop": l.digitTop, "baseline": l.baseline, "dotTop": l.dotTop,
                "ringInner": [l.ringInner.minX, l.ringInner.maxX],
            ])
        }
        // Agenda top, in points from the window's top edge.
        let agendaTop = (superview as? CalendarContentView).map { c -> CGFloat in
            winHeight - c.agenda.convert(c.agenda.bounds, to: nil).maxY
        } ?? -1
        let info: [String: Any] = ["month": m.grid.month.description, "windowHeight": winHeight,
                                   "gridSize": [bounds.width, bounds.height], "agendaTop": agendaTop, "cells": cells]
        let pb = NSPasteboard(name: Self.qaPasteboard)
        pb.clearContents()
        pb.setData(try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]),
                   forType: .init("com.steveafrost.glance.qa.json"))
        for scale in [1, 2] {
            pb.setData(render(scale: CGFloat(scale), background: background), forType: .init("com.steveafrost.glance.qa.png\(scale)x"))
        }
    }

    private func render(scale: CGFloat, background: NSColor) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size // points, so the context scales by `scale`
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        background.setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        displayIgnoringOpacity(bounds, in: ctx)
        return rep.representation(using: .png, properties: [:])
    }
}
