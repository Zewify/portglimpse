import PortGlimpseCore
import SwiftUI

@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model) {
                PanelFooter(model: delegate.model)
            }
        } label: {
            MenuBarLabel(devCount: delegate.model.devCount, showCount: delegate.model.showCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// "Show all" and Quit; Task 11 adds the Settings menu and the update row.
struct PanelFooter: View {
    @Bindable var model: PanelModel

    var body: some View {
        HStack {
            Toggle("Show all users’ ports", isOn: $model.showAll)
                .toggleStyle(.checkbox)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.softText)
                .tint(Theme.amber)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(Theme.footer)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PanelModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
