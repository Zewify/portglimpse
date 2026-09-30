import AppKit
import SwiftUI

/// Owns the one pop-out window: always on top, on every Space and over full-screen apps,
/// with the traffic lights drawn inside PortGlimpse's own dark header.
@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 420, height: 480)
    static let minimumSize = NSSize(width: 300, height: 240)
    static let autosaveName = "PortGlimpseWindow"

    private let model: PanelModel
    private let content: @MainActor () -> AnyView
    private var window: NSWindow?
    /// True while the window counts as a viewer; a minimised window does not, so its refresh pauses.
    private var isViewing = false

    init(model: PanelModel, content: @escaping @MainActor () -> AnyView) {
        self.model = model
        self.content = content
    }

    /// Opens the window, or brings the open one forward; there is never more than one.
    func show() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            window.makeKey()
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.panel)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: content())
        // The SwiftUI content adds the title bar's height to any minimum it states, and overrides the window's own
        // minSize, so the limit is enforced by windowWillResize instead.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.delegate = self
        // Reopens where it was left; the very first time, it is centred at the default size.
        if !window.setFrameUsingName(Self.autosaveName) { window.center() }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        isViewing = true
        model.viewerAppeared()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, Self.minimumSize.width), height: max(frameSize.height, Self.minimumSize.height))
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard isViewing else { return }
        isViewing = false
        model.viewerDisappeared()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard !isViewing else { return }
        isViewing = true
        model.viewerAppeared()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelConfirmations()
        if isViewing { model.viewerDisappeared() }
        isViewing = false
        window = nil
    }
}

/// Lets the window be dragged by the header: a mouse-down here starts a window drag.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
