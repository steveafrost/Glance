// Draws Glance's app icon at every iconset size.
// Usage: swift script/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Glance.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func draw(size px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824pt rounded square centred in 1024.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: hex(0x313244), ending: hex(0x1E1E2E))!.draw(in: bodyPath, angle: -90)

    // Date box, like the menu bar icon.
    let box = CGRect(x: 262 * s, y: 250 * s, width: 500 * s, height: 500 * s)
    let outer = NSBezierPath(roundedRect: box, xRadius: 110 * s, yRadius: 110 * s)
    outer.lineWidth = 46 * s
    hex(0xCBA6F7).setStroke()
    outer.stroke()
    // Two binder tabs.
    hex(0xCBA6F7).setFill()
    for x in [380.0, 644.0] {
        NSBezierPath(roundedRect: CGRect(x: (x - 23) * s, y: 690 * s, width: 46 * s, height: 120 * s), xRadius: 23 * s, yRadius: 23 * s).fill()
    }
    let text = "9" as NSString
    let font = NSFont.systemFont(ofSize: 330 * s, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: hex(0xCDD6F4)]
    let size = text.size(withAttributes: attrs)
    // draw(at:) takes the bottom of the line box; the baseline is |descender| above it.
    let baselineY = box.midY - font.capHeight / 2 - 30 * s
    text.draw(at: CGPoint(x: box.midX - size.width / 2, y: baselineY + font.descender), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(size: px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("wrote \(out.path)")
