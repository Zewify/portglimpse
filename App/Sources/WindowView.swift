import PortGlimpseCore
import SwiftUI

/// The pop-out window's content. Below 360 points wide the rows switch to their compact layout,
/// and the list always scrolls within whatever height the window has.
struct WindowView<Footer: View>: View {
    static var compactWidth: CGFloat { 360 }
    /// The header must stay taller than the title bar: on macOS 26 a scroll view that meets the title bar gets a tinted
    /// band drawn over the header. The traffic lights are moved down to its centre line by FloatingWindowController.
    static var headerHeight: CGFloat { 44 }

    @Bindable var model: PanelModel
    let footer: Footer

    init(model: PanelModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(compact: geometry.size.width < Self.compactWidth)
                Divider().overlay(Theme.line)
                ScrollView {
                    PortList(model: model, compact: geometry.size.width < Self.compactWidth)
                }
                Divider().overlay(Theme.line)
                footer
            }
        }
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        // The content runs under the transparent title bar so the traffic lights sit in the header's own row.
        .ignoresSafeArea(.container, edges: .top)
        // Escape withdraws a question, through the same key monitor the panel uses;
        // onKeyPress never fires here because nothing holds focus.
        .background(PanelWindowObserver(onEscape: model.withdrawQuestion))
    }

    /// The traffic lights sit over the leading 78 points; the text ignores clicks so the drag handle gets them.
    private func header(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Text("PortGlimpse")
                .font(Theme.title(compact ? 15 : 16))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .allowsHitTesting(false)
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: Self.headerHeight)
        .background(WindowDragHandle())
    }
}

