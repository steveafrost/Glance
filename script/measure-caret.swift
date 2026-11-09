// Usage: swift script/measure-caret.swift shown.png hidden.png
// Prints the caret apex centre (x, from the first rows that differ between
// the two captures) and each date-box cluster in the menu bar row band.
import AppKit
func load(_ p: String) -> NSBitmapImageRep { NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: p)))! }
let a = load(CommandLine.arguments[1]), b = load(CommandLine.arguments[2])
func diff(_ x: Int, _ y: Int) -> Bool {
    guard let c1 = a.colorAt(x: x, y: y), let c2 = b.colorAt(x: x, y: y) else { return false }
    return abs(c1.redComponent - c2.redComponent) + abs(c1.greenComponent - c2.greenComponent) + abs(c1.blueComponent - c2.blueComponent) > 0.25
}
var rows: [(Int, Int, Int)] = []
for y in 30..<a.pixelsHigh {
    let xs = (0..<a.pixelsWide).filter { diff($0, y) }
    if !xs.isEmpty { rows.append((y, xs.min()!, xs.max()!)) }
    if rows.count == 4 { break }
}
for (y, lo, hi) in rows { print("row \(y): x \(lo)-\(hi) centre \(Double(lo + hi + 1) / 2)") }
