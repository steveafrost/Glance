// Measures the vertical extent of glyphs in a menu bar screenshot.
// Usage: swift script/measure-menubar.swift <png> [minX maxX label]...
// Without ranges it auto-detects glyph clusters (columns with foreground
// pixels, split on gaps of 4+ empty columns) and prints each cluster's
// x range and first/last ink row (0 = top of the screenshot).
import AppKit

let args = CommandLine.arguments
guard args.count >= 2, let image = NSImage(contentsOfFile: args[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: measure-menubar.swift <png> [minX maxX label]...\n".data(using: .utf8)!)
    exit(2)
}
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func lum(_ x: Int, _ y: Int) -> Double {
    let i = (y * w + x) * 4
    return 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
}
// Background per row: median luminance of the row (glyphs are sparse).
var bg = [Double](repeating: 0, count: h)
for y in 0..<h { bg[y] = (0..<w).map { lum($0, y) }.sorted()[w / 2] }
let threshold = 40.0
func ink(_ x: Int, _ y: Int) -> Bool { abs(lum(x, y) - bg[y]) > threshold }

func rows(_ x0: Int, _ x1: Int) -> (Int, Int)? {
    var top: Int?, bottom: Int?
    for y in 0..<h { for x in x0...x1 where ink(x, y) { top = top ?? y; bottom = y; break } }
    guard let t = top, let b = bottom else { return nil }
    return (t, b)
}
func report(_ x0: Int, _ x1: Int, _ label: String) {
    guard let (t, b) = rows(x0, x1) else { print("\(label): no ink"); return }
    let centre = Double(t + b) / 2
    print(String(format: "%@ x %d-%d  rows %d-%d  height %d  centre %.1f", label, x0, x1, t, b, b - t + 1, centre))
}

if args.count >= 5 {
    var i = 2
    while i + 2 < args.count + 0 && i + 2 <= args.count - 1 {
        report(Int(args[i])!, Int(args[i + 1])!, args[i + 2]); i += 3
    }
} else {
    var clusters: [(Int, Int)] = []
    var start: Int?, lastInk = -100
    for x in 0..<w {
        let has = (0..<h).contains { ink(x, $0) }
        if has {
            if start == nil || x - lastInk > 4 { if let s = start { clusters.append((s, lastInk)) }; start = x }
            lastInk = x
        }
    }
    if let s = start { clusters.append((s, lastInk)) }
    for (i, c) in clusters.enumerated() { report(c.0, c.1, "cluster\(i)") }
}
