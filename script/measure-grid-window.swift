// Prints the window number of Glance's calendar popover (status-bar layer).
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
if let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "Glance" && ($0[kCGWindowLayer as String] as? Int) == 24 }) {
    print(w[kCGWindowNumber as String] as! Int)
}
