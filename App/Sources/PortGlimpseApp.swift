import PortGlimpseCore
import SwiftUI

@main
struct PortGlimpseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model, onPopOut: { delegate.popOut() }) {
                PanelFooter(model: delegate.model, loginItem: delegate.loginItem, updates: delegate.updates)
            }
        } label: {
            MenuBarLabel(devCount: delegate.model.devCount, showCount: delegate.model.showCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// "Show all", the Settings menu and Quit, with an update row above them when a newer release exists.
struct PanelFooter: View {
    @Bindable var model: PanelModel
    let loginItem: LoginItem
    @Bindable var updates: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            if let version = updates.available {
                HStack {
                    Text(verbatim: "Update available: \(version)").font(Theme.body(13, .semibold)).foregroundStyle(Theme.amber)
                    Spacer()
                    Button("Copy install command") { updates.copyInstallCommand() }.buttonStyle(PanelButtonStyle(.ghost))
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                Divider().overlay(Theme.line)
            }
            HStack(spacing: 4) {
                // The narrow pop-out window gets the short label rather than a truncated long one.
                ViewThatFits(in: .horizontal) {
                    showAllToggle("Show all users’ ports")
                    showAllToggle("Show all")
                }
                Spacer(minLength: 4)
                Menu("Settings") {
                    Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    Toggle("Show count in menu bar", isOn: $model.showCount)
                    Toggle("Check for updates", isOn: $updates.isEnabled)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(Theme.body(13, .semibold))
                .foregroundStyle(Theme.muted)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .background(Theme.footer)
    }

    private func showAllToggle(_ title: String) -> some View {
        Toggle(title, isOn: $model.showAll)
            .toggleStyle(.checkbox)
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.softText)
            .tint(Theme.amber)
            .lineLimit(1)
            .fixedSize()
            .help("Show all users’ ports")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PanelModel()
    let loginItem = LoginItem()
    let updates = UpdateChecker()
    lazy var window = FloatingWindowController(model: model) { [unowned self] in
        AnyView(WindowView(model: model) {
            PanelFooter(model: model, loginItem: loginItem, updates: updates)
        })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        updates.start()
        loginItem.enableOnFirstLaunch()
    }

    /// Opens the window and closes the menu bar panel.
    /// The panel is closed the way a click on its icon closes it: closing or hiding its window directly
    /// leaves MenuBarExtra believing it is still open, and the next click on the icon would do nothing.
    func popOut() {
        window.show()
        Self.statusItemButton()?.performClick(nil)
    }

    private static func statusItemButton() -> NSButton? {
        func button(in view: NSView) -> NSButton? {
            if let found = view as? NSButton { return found }
            for child in view.subviews { if let found = button(in: child) { return found } }
            return nil
        }
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let content = window.contentView, let found = button(in: content) { return found }
        }
        return nil
    }
}
