import AppKit
import SwiftUI

/// The Settings window: an ordinary window, since there's a list to work
/// through rather than a quick action.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 560, height: 640)

    var onShow: (() -> Void)?
    var onClose: (() -> Void)?

    private let makeView: () -> SettingsView
    private var window: NSWindow?

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        onShow?()
        // A menu bar app has no Dock icon to bring it forward; activate it so
        // the window comes up in front and takes the keyboard.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "\(AppVariant.name) Settings"
        window.contentView = NSHostingView(rootView: makeView())
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
