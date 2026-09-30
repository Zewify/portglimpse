// Renders AppIcon.appiconset: an amber keycap with a colon on TickThock's dark tile.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // macOS icon grid: an 824-point tile inset 100 points in the 1024 canvas.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(color(0x221E1B))
    ctx.fillPath()
    // The key's darker skirt, then its face on top; the skirt shows as a band along the bottom.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 262, y: 238, width: 500, height: 520), cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.setFillColor(color(0xB9531A))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 262, y: 290, width: 500, height: 468), cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.clip()
    let face = CGGradient(colorsSpace: space, colors: [color(0xFFB067), color(0xEE8237)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(face, start: CGPoint(x: 512, y: 758), end: CGPoint(x: 512, y: 290), options: [])
    ctx.restoreGState()
    // The colon.
    ctx.setFillColor(color(0x1B1815))
    for centre in [CGFloat(434), 614] {
        ctx.fillEllipse(in: CGRect(x: 512 - 44, y: centre - 44, width: 88, height: 88))
    }
    let bitmap = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icons to \(output.path)")
