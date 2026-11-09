// Measures how far each day cell's event-dot row sits from the centre of
// the day number's ink, in points.
//
//   swift script/measure-grid.swift extract DIR        # QA pasteboard -> DIR/{grid.json,render1x.png,render2x.png}
//   swift script/measure-grid.swift measure JSON PNG window|grid SCALE [label]
//
// "window" PNGs are `screencapture -o -l` shots of the calendar window
// (cells use the dump's window rects); "grid" PNGs are the offscreen renders.
import AppKit

let args = CommandLine.arguments
func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

if args.count >= 3, args[1] == "extract" {
    let dir = URL(fileURLWithPath: args[2])
    let pb = NSPasteboard(name: .init("com.steveafrost.Glance.qa"))
    for (type, name) in [("json", "grid.json"), ("png1x", "render1x.png"), ("png2x", "render2x.png")] {
        guard let d = pb.data(forType: .init("com.steveafrost.glance.qa.\(type)")) else { fail("no \(type) on the QA pasteboard") }
        try! d.write(to: dir.appendingPathComponent(name))
    }
    exit(0)
}
guard args.count >= 6, args[1] == "measure" else { fail("usage: see header") }

let info = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[3]))) else { fail("bad png") }
let useWindow = args[4] == "window", s = Double(args[5])!, label = args.count > 6 ? args[6] : ""

// Raw 8-bit RGB access (colorAt is slow and colour-managed).
let bmp = rep.bitmapData!, bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    let o = y * bpr + x * spp
    return (Double(bmp[o]), Double(bmp[o + 1]), Double(bmp[o + 2]))
}
func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let d = (a.0 - b.0, a.1 - b.1, a.2 - b.2); return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
}

/// Coverage (0...1) of foreground in a pixel box, against the box's most common colour.
func coverage(x0: Int, x1: Int, y0: Int, y1: Int) -> [[Double]] {
    var counts: [Int: Int] = [:]
    for y in y0..<y1 { for x in x0..<x1 { let p = px(x, y); counts[(Int(p.0) / 4) << 16 | (Int(p.1) / 4) << 8 | Int(p.2) / 4, default: 0] += 1 } }
    var bgSum = (0.0, 0.0, 0.0), n = 0.0
    let mode = counts.max { $0.value < $1.value }!.key
    for y in y0..<y1 { for x in x0..<x1 { let p = px(x, y)
        if (Int(p.0) / 4) << 16 | (Int(p.1) / 4) << 8 | Int(p.2) / 4 == mode { bgSum = (bgSum.0 + p.0, bgSum.1 + p.1, bgSum.2 + p.2); n += 1 } } }
    let bg = (bgSum.0 / n, bgSum.1 / n, bgSum.2 / n)
    var d = (y0..<y1).map { y in (x0..<x1).map { x in dist(px(x, y), bg) } }
    let peak = d.joined().max() ?? 1
    d = d.map { $0.map { peak > 0 ? min($0 / peak, 1) : 0 } }
    return d
}

struct Row { var day: Int; var flags: String; var dots: Int; var ink: Double; var dot: Double; var off: Double }
var rows: [Row] = []
for c in info["cells"] as! [[String: Any]] {
    let dots = c["dots"] as! Int
    guard dots > 0 else { continue }
    let r = (c[useWindow ? "window" : "grid"] as! [Double])
    let ox = r[0], oy = r[1]
    let ring = c["ringInner"] as! [Double]
    // Horizontal span inside the ring, clear of its stroke.
    let xa = Int(((ox + ring[0] + 0.5) * s).rounded(.up)), xb = Int(((ox + ring[1] - 0.5) * s).rounded(.down))
    // Digit band: cap top to baseline. Dot band: exactly the 4pt dot rows (clear of the ring's rounded corners).
    let digitTop = c["digitTop"] as! Double, baseline = c["baseline"] as! Double, dotTop = c["dotTop"] as! Double
    let d = coverage(x0: xa, x1: xb, y0: Int(((oy + digitTop - 0.5) * s).rounded(.down)), y1: Int(((oy + baseline + 0.5) * s).rounded(.up)))
    let cols = (0..<(xb - xa)).map { x in d.map { $0[x] }.max()! }
    guard let first = cols.firstIndex(where: { $0 > 0.04 }), let last = cols.lastIndex(where: { $0 > 0.04 }) else { continue }
    // Fractional ink edges from the antialiased edge columns.
    let left = Double(first) + 1 - cols[first], right = Double(last) + cols[last]
    let ink = (Double(xa) + (left + right) / 2) / s

    let e = coverage(x0: xa, x1: xb, y0: Int(((oy + dotTop) * s).rounded(.down)), y1: Int(((oy + dotTop + 4) * s).rounded(.up)))
    let dc = (0..<(xb - xa)).map { x in e.map { $0[x] }.reduce(0, +) }
    // Split into dots at empty columns; average their centroids.
    var centres: [Double] = [], w = 0.0, wx = 0.0
    for (x, v) in dc.enumerated() + [(dc.count, 0)] {
        if v > 0.05 { w += v; wx += v * (Double(x) + 0.5) } else if w > 0 { centres.append(wx / w); w = 0; wx = 0 }
    }
    guard !centres.isEmpty else { continue }
    let dot = (Double(xa) + centres.reduce(0, +) / Double(centres.count)) / s
    let flags = ((c["today"] as! Bool) ? "T" : "") + ((c["selected"] as! Bool) ? "S" : "")
    rows.append(Row(day: c["day"] as! Int, flags: flags, dots: dots, ink: ink, dot: dot, off: dot - ink))
    if centres.count != min(dots, 3) { FileHandle.standardError.write("day \(c["day"]!): saw \(centres.count) dots, expected \(dots)\n".data(using: .utf8)!) }
}
let worst = rows.map { abs($0.off) }.max() ?? 0
let mean = rows.map { abs($0.off) }.reduce(0, +) / Double(max(rows.count, 1))
print("## \(info["month"]!) \(label) @\(Int(s))x: \(rows.count) cells with dots, worst \(String(format: "%.2f", worst))pt, mean |off| \(String(format: "%.2f", mean))pt")
print("day flags dots  ink-x   dot-x   offset")
for r in rows {
    print(String(format: "%3d %-5@ %4d %7.2f %7.2f %+7.2f%@", r.day, r.flags as NSString, r.dots, r.ink, r.dot, r.off, abs(r.off) > 0.5 ? " !" as NSString : "" as NSString))
}
