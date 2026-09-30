// Prints the CGWindowID and size of every on-screen PortGlimpse window, for `screencapture -l`.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "PortGlimpse" {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let layer = window[kCGWindowLayer as String] as? Int, layer != 25 else { continue } // 25 = the status item
    print("\(id) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))")
}
