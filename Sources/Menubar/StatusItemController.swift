import AppKit

/// The chevron. A click opens or closes the section of icons set to "On
/// click"; a right-click (or Control-click) offers Settings and Quit.
final class StatusItemController: NSObject {
    var onToggle: (() -> Void)?
    var onShowSettings: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var appearanceObservation: NSKeyValueObservation?
    private var revealed = false

    override init() {
        super.init()
        item.autosaveName = "Menubar"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // The dev build's coloured image follows the menu bar's light or dark look.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.render() }
            }
        }
        render()
    }

    func setRevealed(_ revealed: Bool) {
        guard revealed != self.revealed else { return }
        self.revealed = revealed
        render()
    }

    private func render() {
        guard let button = item.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = ChevronRenderer.image(revealed: revealed, devMarker: AppVariant.isDev, darkMenuBar: dark)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onToggle?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Settings…", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit \(AppVariant.name)", #selector(quit)))

        // Attaching the menu only for this click keeps left-click free for the toggle.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func showSettings() { onShowSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
