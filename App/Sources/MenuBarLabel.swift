import AppKit
import SwiftUI

/// TickThock's dark tile with the amber colon from every port label, drawn in full colour at menu bar size.
@MainActor
enum MenuBarIcon {
    /// Menu bar icons are 18 points tall.
    private static let size = NSSize(width: 18, height: 18)

    private static let normal = render(opacity: 1)
    private static let dim = render(opacity: 0.4)

    static func image(dimmed: Bool) -> NSImage { dimmed ? dim : normal }

    /// Drawn on demand, so it stays sharp at whatever scale the menu bar's display uses.
    private static func render(opacity: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            NSColor(srgbRed: 0x22 / 255, green: 0x1E / 255, blue: 0x1B / 255, alpha: opacity).setFill()
            tile.fill()
            NSColor(srgbRed: 0xF4 / 255, green: 0x8E / 255, blue: 0x48 / 255, alpha: opacity).setFill()
            for centreY in [5.8, 12.2] {
                NSBezierPath(ovalIn: NSRect(x: 9 - 1.8, y: centreY - 1.8, width: 3.6, height: 3.6)).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "PortGlimpse"
        return image
    }
}

/// The icon plus the number of dev servers; faded with no number when there are none.
struct MenuBarLabel: View {
    let devCount: Int
    let showCount: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(dimmed: devCount == 0))
            if showCount, devCount > 0 {
                Text(verbatim: "\(devCount)").monospacedDigit()
            }
        }
    }
}
