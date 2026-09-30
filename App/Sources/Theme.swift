import SwiftUI

/// TickThock's dark palette and type, shared by every view.
enum Theme {
    static let page = Color(hex: 0x16130F)
    static let panel = Color(hex: 0x201B17)
    static let raised = Color(hex: 0x2A241F)
    static let footer = Color(hex: 0x1B1714)
    static let text = Color(hex: 0xF6EDE3)
    static let softText = Color(hex: 0xD8CBBD)
    static let muted = Color(hex: 0xA8998A)
    static let line = Color(hex: 0x342C25)
    static let lineStrong = Color(hex: 0x4A3F35)
    static let amber = Color(hex: 0xF48E48)
    static let amberFace = LinearGradient(colors: [Color(hex: 0xFFB067), Color(hex: 0xEE8237)], startPoint: .top, endPoint: .bottom)
    static let onAmber = Color(hex: 0x1B1815)
    static let amberTint = Color(hex: 0x2C211A)
    static let amberTintLine = Color(hex: 0x4D3424)
    static let cap = Color(hex: 0x2E2721)
    static let capInk = Color(hex: 0xE9DDD0)

    static func title(_ size: CGFloat) -> Font { .custom("Bricolage Grotesque", size: size).weight(.heavy) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Figtree", size: size).weight(weight) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBM Plex Mono", size: size).weight(.semibold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Flat 30-point buttons: a keycap-coloured ghost, or the amber primary used only for Kill and Force kill.
struct PanelButtonStyle: ButtonStyle {
    enum Kind { case ghost, primary }
    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(kind == .primary ? Theme.onAmber : Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(kind == .primary ? AnyShapeStyle(Theme.amberFace) : AnyShapeStyle(Theme.cap), in: shape)
            .overlay(shape.strokeBorder(kind == .primary ? Color.clear : Theme.lineStrong))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(shape)
    }
}
