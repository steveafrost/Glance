import AppKit
import GlanceCore
import os

private let log = Logger(subsystem: "com.steveafrost.Glance", category: "app")

/// QA only (`--qa-keys dump-popover`): renders the whole calendar popover —
/// header, month grid and agenda — to a PNG through `cacheDisplay`, which draws
/// into a bitmap rather than reading the screen. That means it needs no Screen
/// Recording permission, so docs images can be produced on any machine,
/// including one with no calendar account (`--qa-demo-data`).
extension CalendarContentView {
    static let popoverPasteboard = NSPasteboard.Name("com.steveafrost.Glance.qa")

    /// Transparent margin around the card, in points.
    private static let padding: CGFloat = 20
    /// Corner radius of the card, matching the popover's own shape.
    private static let cornerRadius: CGFloat = 12

    /// Render at `scale` (2 = Retina) and publish on the QA pasteboard, or write
    /// to `path` when given. A relative `path` lands in the app's container tmp;
    /// the sandbox blocks writes elsewhere.
    func publishPopoverDump(background: NSColor, path: String?, scale: CGFloat = 2) {
        layoutSubtreeIfNeeded()
        let card = bounds.size
        guard card.width > 1, card.height > 1 else {
            log.notice("qa dump-popover: content view has no size")
            return
        }
        let pad = Self.padding
        let total = CGSize(width: card.width + pad * 2, height: card.height + pad * 2)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((total.width * scale).rounded()),
            pixelsHigh: Int((total.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = total // points, so the context scales by `scale`
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

        // Pass 1: draw the popover into its own bitmap. `cacheDisplay` always
        // draws at the destination bitmap's origin, so it cannot be offset
        // directly — the card is composited instead.
        guard let cardRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((card.width * scale).rounded()),
            pixelsHigh: Int((card.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        cardRep.size = card
        guard let cardCtx = NSGraphicsContext(bitmapImageRep: cardRep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = cardCtx
        cardCtx.cgContext.setFillColor(background.cgColor)
        cardCtx.cgContext.fill(CGRect(origin: .zero, size: card))
        cacheDisplay(in: bounds, to: cardRep)
        NSGraphicsContext.restoreGraphicsState()

        // Pass 2: rounded card on a transparent margin, so the image reads as a
        // floating panel on any page background.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        let cardRect = CGRect(x: pad, y: pad, width: card.width, height: card.height)
        cg.addPath(CGPath(roundedRect: cardRect, cornerWidth: Self.cornerRadius,
                          cornerHeight: Self.cornerRadius, transform: nil))
        cg.clip()
        cg.draw(cardRep.cgImage!, in: cardRect)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let dims = "\(Int(total.width))x\(Int(total.height))@\(Int(scale))x"

        if let path {
            let resolved = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path)
            do {
                try data.write(to: resolved)
                log.notice("qa dump-popover wrote \(resolved.path, privacy: .public) \(dims, privacy: .public)")
            } catch {
                log.notice("qa dump-popover write failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            let pb = NSPasteboard(name: Self.popoverPasteboard)
            pb.clearContents()
            pb.setData(data, forType: .init("com.steveafrost.glance.popover.png"))
            log.notice("qa dump-popover published \(dims, privacy: .public)")
        }
    }
}
