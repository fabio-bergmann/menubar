import AppKit

/// The chevron. A click opens or closes the section of icons set to "On
/// click"; a right-click (or Control-click) offers Settings and Quit.
final class StatusItemController: NSObject {
    var onToggle: (() -> Void)?
    var onShowSettings: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var appearanceObservation: NSKeyValueObservation?
    private var revealed = false
    /// What the image was last drawn for. Setting an image makes macOS
    /// redraw the item's copies in the menu bar, which reports an appearance
    /// change, so redrawing on every report would never stop.
    private var drawn: (revealed: Bool, dark: Bool)?

    override init() {
        super.init()
        item.autosaveName = "Menubar"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // Only the dev build's coloured image follows the menu bar's light
            // or dark look; a template image is tinted by macOS.
            if AppVariant.isDev {
                appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.render() }
                }
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
        let dark = AppVariant.isDev && button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let drawn, drawn.revealed == revealed, drawn.dark == dark { return }
        drawn = (revealed, dark)
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
