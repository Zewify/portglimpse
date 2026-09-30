import PortGlimpseCore
import SwiftUI

/// The menu bar panel: header, the shared list, and a footer supplied by the caller.
struct PanelView<Footer: View>: View {
    @Bindable var model: PanelModel
    /// Set by Task 12; when nil the header has no pop-out button.
    let onPopOut: (() -> Void)?
    let footer: Footer

    /// Past this height the list scrolls instead of growing off the screen.
    static var maxListHeight: CGFloat { 600 }

    /// The list's natural height, measured, so hidden rows (collapsed sections) never count.
    @State private var listHeight: CGFloat = 0

    init(model: PanelModel, onPopOut: (() -> Void)? = nil, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.onPopOut = onPopOut
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if listHeight > Self.maxListHeight {
                ScrollView { measuredList }.frame(height: Self.maxListHeight)
            } else {
                measuredList
            }
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 408)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .background(PanelWindowObserver(onOpen: model.panelOpened, onClose: model.panelClosed, onEscape: model.withdrawQuestion))
    }

    private var measuredList: some View {
        PortList(model: model)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("PortGlimpse").font(Theme.title(18)).tracking(-0.5).foregroundStyle(Theme.text)
            Spacer()
            if let onPopOut {
                IconButton(symbol: "macwindow.on.rectangle", label: "Open in a window", action: onPopOut)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 46)
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
