// Composes App Store screenshots from the QA-rendered window PNGs.
//
// The store wants 16:10 (2880x1800 for Mac), but the app's own renders are
// window-shaped: the popover is tall and narrow, settings are near-square.
// Rather than upscale or crop, this lays each render out beside its headline,
// which keeps the app at its real pixel density and fills the frame.
//
//   swift script/make-store-shots.swift [output-dir]
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1] : "build/mas/shots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let canvasWidth = 2880
let canvasHeight = 1800

func rgb(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

struct Theme {
    let background: UInt32
    let panel: UInt32
    let text: UInt32
    let accent: UInt32
    let name: String
}

// Colours are the app's own Catppuccin values, so the frame matches the app.
let themes = [
    Theme(background: 0xEFF1F5, panel: 0xE6E9EF, text: 0x4C4F69,
          accent: 0x1E66F5, name: "latte"),
    Theme(background: 0x1E1E2E, panel: 0x181825, text: 0xCDD6F4,
          accent: 0x89B4FA, name: "mocha"),
]

struct Shot {
    let file: String
    let title: String
    let sub: String
}

let shots = [
    Shot(file: "docs/popover", title: "Today, where\nyou already look",
         sub: "A month grid and agenda in the\nmenu bar. No window to manage."),
    Shot(file: "docs/settings-appearance", title: "Six themes,\nlight and dark",
         sub: "Native system colours, or any\nCatppuccin flavour."),
    Shot(file: "docs/editor", title: "Edit without\nswitching apps",
         sub: "Create and change events right\nwhere you found them."),
]

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

for theme in themes {
    for (index, shot) in shots.enumerated() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasWidth,
                                   pixelsHigh: canvasHeight, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        rep.size = NSSize(width: canvasWidth, height: canvasHeight)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        rgb(theme.background).setFill()
        NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()

        // Left column: the headline. Right side belongs to the app render.
        let textWidth: CGFloat = 940
        let textX: CGFloat = 190

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: font(104, .bold), .foregroundColor: rgb(theme.text),
            .paragraphStyle: paragraph,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: font(46, .regular),
            .foregroundColor: rgb(theme.text).withAlphaComponent(0.7),
            .paragraphStyle: paragraph,
        ]

        // Measure so the block sits optically centred in the left column.
        let titleBound = (shot.title as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 600),
            options: [.usesLineFragmentOrigin], attributes: titleAttrs)
        let subBound = (shot.sub as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 400),
            options: [.usesLineFragmentOrigin], attributes: subAttrs)
        let blockHeight = titleBound.height + 44 + subBound.height
        let blockTop = (CGFloat(canvasHeight) + blockHeight) / 2

        (shot.title as NSString).draw(
            in: NSRect(x: textX, y: blockTop - titleBound.height,
                       width: textWidth, height: titleBound.height),
            withAttributes: titleAttrs)
        (shot.sub as NSString).draw(
            in: NSRect(x: textX, y: blockTop - titleBound.height - 44 - subBound.height,
                       width: textWidth, height: subBound.height),
            withAttributes: subAttrs)

        // A short accent rule under the headline, in the theme's link colour.
        rgb(theme.accent).setFill()
        NSBezierPath(roundedRect: NSRect(x: textX, y: blockTop + 56, width: 96, height: 8),
                     xRadius: 4, yRadius: 4).fill()

        // The app render, scaled to fit the remaining width and full height.
        let source = URL(fileURLWithPath: "\(shot.file)-\(theme.name).png")
        if let image = NSImage(contentsOf: source) {
            let areaX: CGFloat = 1220
            let areaWidth = CGFloat(canvasWidth) - areaX - 120
            let areaHeight = CGFloat(canvasHeight) - 260
            let scale = min(areaWidth / image.size.width, areaHeight / image.size.height)
            let drawWidth = image.size.width * scale
            let drawHeight = image.size.height * scale
            let rect = NSRect(x: areaX + (areaWidth - drawWidth) / 2,
                              y: (CGFloat(canvasHeight) - drawHeight) / 2,
                              width: drawWidth, height: drawHeight)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        NSGraphicsContext.restoreGraphicsState()
        let name = "\(String(format: "%02d", index + 1))-\(theme.name).png"
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outDir.appendingPathComponent(name))
            print("wrote \(name) \(canvasWidth)x\(canvasHeight)")
        }
    }
}
