import AppKit
import os

private let log = Logger(subsystem: "com.steveafrost.Glance", category: "app")

/// QA only: renders a whole window — titlebar, toolbar and content — to a PNG
/// through `cacheDisplay`, which draws into a bitmap rather than reading the
/// screen. That means it needs no Screen Recording permission, so docs images
/// can be produced on any machine, including one with no calendar account
/// (`--qa-demo-data`).
///
/// `CalendarContentView.publishPopoverDump` handles the borderless popover,
/// which has no titlebar; this handles real windows like Settings.
enum WindowQADump {
    static let pasteboard = NSPasteboard.Name("com.steveafrost.Glance.qa")
    static let pngType = NSPasteboard.PasteboardType("com.steveafrost.glance.window.png")

    /// Transparent margin around the window, in points.
    private static let padding: CGFloat = 20
    /// Corner radius of the window's card.
    private static let cornerRadius: CGFloat = 10

    /// Render `window` at `scale` and publish it on the QA pasteboard.
    ///
    /// The window is ordered front first so its titlebar and toolbar have a
    /// backing layer to draw into; `--keep-open` stops the calendar hiding
    /// itself when that makes the app active.
    @MainActor
    static func publish(_ window: NSWindow, label: String, scale: CGFloat = 2) {
        guard let view = window.contentView?.superview ?? window.contentView else {
            log.notice("qa dump-\(label, privacy: .public): no content view")
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        view.layoutSubtreeIfNeeded()

        let frame = view.bounds
        guard frame.width > 1, frame.height > 1 else {
            log.notice("qa dump-\(label, privacy: .public): window has no size")
            return
        }

        // Pass 1: the window into its own bitmap. `cacheDisplay` always draws at
        // the destination bitmap's origin, so it cannot be offset directly.
        guard let cardRep = bitmap(size: frame.size, scale: scale) else { return }
        cardRep.size = frame.size
        guard let cardCtx = NSGraphicsContext(bitmapImageRep: cardRep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = cardCtx
        view.cacheDisplay(in: frame, to: cardRep)
        NSGraphicsContext.restoreGraphicsState()

        // Pass 2: rounded card on a transparent margin, so the image reads as a
        // floating window on any page background.
        let pad = padding
        let total = CGSize(width: frame.width + pad * 2, height: frame.height + pad * 2)
        guard let rep = bitmap(size: total, scale: scale) else { return }
        rep.size = total
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        let cardRect = CGRect(x: pad, y: pad, width: frame.width, height: frame.height)
        cg.addPath(CGPath(roundedRect: cardRect, cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius, transform: nil))
        cg.clip()
        if let image = cardRep.cgImage { cg.draw(image, in: cardRect) }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard(name: pasteboard)
        pb.clearContents()
        pb.setData(data, forType: pngType)
        let dims = "\(Int(total.width))x\(Int(total.height))@\(Int(scale))x"
        log.notice("qa dump-\(label, privacy: .public) published \(dims, privacy: .public)")
    }

    private static func bitmap(size: CGSize, scale: CGFloat) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * scale).rounded()),
            pixelsHigh: Int((size.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
    }
}
