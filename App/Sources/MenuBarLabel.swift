import AppKit
import SwiftUI

/// The colon keycap, drawn as a template image so macOS tints it for the menu bar.
@MainActor
enum KeycapGlyph {
    private static let normal = draw(alpha: 1)
    private static let dim = draw(alpha: 0.5)

    static func image(dimmed: Bool) -> NSImage { dimmed ? dim : normal }

    private static func draw(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let ink = NSColor.black.withAlphaComponent(alpha)
            let key = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 2.25, width: 11.5, height: 11.5), xRadius: 3, yRadius: 3)
            key.lineWidth = 1.5
            ink.setStroke()
            key.stroke()
            ink.setFill()
            for centreY in [6.0, 10.0] {
                NSBezierPath(ovalIn: NSRect(x: 8 - 1.2, y: centreY - 1.2, width: 2.4, height: 2.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PortGlimpse"
        return image
    }
}

/// The icon plus the number of dev servers; dimmed with no number when there are none.
struct MenuBarLabel: View {
    let devCount: Int
    let showCount: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: KeycapGlyph.image(dimmed: devCount == 0))
            if showCount, devCount > 0 {
                Text(verbatim: "\(devCount)").monospacedDigit()
            }
        }
    }
}
