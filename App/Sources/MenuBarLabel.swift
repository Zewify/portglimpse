import AppKit
import SwiftUI

/// The app icon's tile in full colour, drawn the same way as TickThock's so the two read as siblings.
@MainActor
enum MenuBarIcon {
    /// Menu bar icons are 18 points tall; the app icon's tile fills that once its transparent margin is cropped.
    private static let size = NSSize(width: 18, height: 18)

    private static let normal = render(opacity: 1)
    private static let dim = render(opacity: 0.4)

    static func image(dimmed: Bool) -> NSImage { dimmed ? dim : normal }

    /// Drawn on demand, so it stays sharp at whatever scale the menu bar's display uses.
    private static func render(opacity: CGFloat) -> NSImage {
        let icon = NSApp.applicationIconImage ?? NSImage()
        let image = NSImage(size: size, flipped: false) { rect in
            // The icon's squircle spans 100...924 of its 1024-point canvas (scripts/make-icon.swift).
            let tile = NSRect(x: icon.size.width * 100 / 1024, y: icon.size.height * 100 / 1024,
                              width: icon.size.width * 824 / 1024, height: icon.size.height * 824 / 1024)
            icon.draw(in: rect, from: tile, operation: .sourceOver, fraction: opacity)
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
