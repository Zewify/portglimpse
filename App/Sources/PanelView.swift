import PortGlimpseCore
import SwiftUI

/// The menu bar panel: header, the shared list, and a footer supplied by the caller.
struct PanelView<Footer: View>: View {
    @Bindable var model: PanelModel
    /// Set by Task 12; when nil the header has no pop-out button.
    let onPopOut: (() -> Void)?
    let footer: Footer

    /// Past this many rows the list scrolls instead of growing off the screen.
    static var scrollThreshold: Int { 12 }

    init(model: PanelModel, onPopOut: (() -> Void)? = nil, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.onPopOut = onPopOut
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if model.rows.count > Self.scrollThreshold {
                ScrollView { PortList(model: model) }.frame(height: 600)
            } else {
                PortList(model: model)
            }
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 408)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .background(PanelWindowObserver(onOpen: model.panelOpened, onClose: model.panelClosed, onEscape: model.withdrawQuestion))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("PortGlimpse").font(Theme.title(18)).tracking(-0.5).foregroundStyle(Theme.text)
            Spacer()
            LiveBadge()
            if let onPopOut {
                IconButton(symbol: "macwindow.on.rectangle", label: "Open in a window", action: onPopOut)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 46)
    }
}

/// The amber "Live" dot shown in both headers.
struct LiveBadge: View {
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.amber).frame(width: 7, height: 7)
                .background(Circle().fill(Theme.amber.opacity(0.18)).frame(width: 13, height: 13))
            if showsLabel {
                Text("Live").font(Theme.body(12, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Updating live")
    }
}
