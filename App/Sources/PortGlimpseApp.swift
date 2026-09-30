import SwiftUI
import PortGlimpseCore

@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Text("PortGlimpse")
                .font(Theme.title(18))
                .foregroundStyle(Theme.text)
                .padding(24)
                .background(Theme.panel)
        } label: {
            MenuBarLabel(devCount: 0, showCount: true)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {}
