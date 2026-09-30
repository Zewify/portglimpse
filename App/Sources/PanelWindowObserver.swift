import AppKit
import SwiftUI

/// Tells the model when the menu bar panel opens and closes.
/// A window-style MenuBarExtra keeps its view alive between openings, so onAppear is not enough;
/// the panel's window becomes key when shown and resigns key when dismissed.
struct PanelWindowObserver: NSViewRepresentable {
    let onOpen: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    /// Returns true when it used the key; otherwise Escape reaches the panel and dismisses it.
    let onEscape: @MainActor () -> Bool

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onOpen = onOpen
        view.onClose = onClose
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        var onOpen: (@MainActor () -> Void)?
        var onClose: (@MainActor () -> Void)?
        var onEscape: (@MainActor () -> Bool)?
        private var tokens: [NSObjectProtocol] = []
        private var keyMonitor: Any?

        /// True between an onOpen and its matching onClose, so the two always pair up.
        private var reportedOpen = false

        isolated deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private func reportOpen() {
            guard !reportedOpen else { return }
            reportedOpen = true
            onOpen?()
        }

        private func reportClose() {
            guard reportedOpen else { return }
            reportedOpen = false
            onClose?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            // Leaving a window (or all windows) while it was key counts as closing.
            reportClose()
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportOpen() }
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportClose() }
            })
            // Escape withdraws a question. A key monitor works whatever the panel's focus is,
            // which onKeyPress does not: nothing in the panel holds focus until the user tabs.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, self.window?.isKeyWindow == true else { return event }
                let used = MainActor.assumeIsolated { self.onEscape?() ?? false }
                return used ? nil : event
            }
            if window.isKeyWindow { reportOpen() }
        }
    }
}
