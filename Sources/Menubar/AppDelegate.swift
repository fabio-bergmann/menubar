import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let inventory = MenuBarInventory()
    private let concealer = Concealer()
    private let updates = UpdateService()
    private var clockClicks: ClockClicks?
    private var statusItem: StatusItemController?
    private var controller: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var settingsRescan: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning {
            NSApp.terminate(nil)
            return
        }

        let statusItem = StatusItemController()
        let controller = MenuBarController(
            settings: settings, concealer: concealer, inventory: inventory, statusItem: statusItem
        )
        let settingsWindow = SettingsWindowController { [settings, inventory, concealer, updates] in
            SettingsView(settings: settings, inventory: inventory, hiding: concealer, updates: updates)
        }
        // While Settings is open its list follows apps adding and removing icons.
        settingsWindow.onShow = { [weak self] in
            guard let self else { return }
            inventory.scan()
            concealer.checkForOtherManagers()
            settingsRescan?.invalidate()
            settingsRescan = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.inventory.scan()
                self?.concealer.checkForOtherManagers()
            }
        }
        settingsWindow.onClose = { [weak self] in
            self?.settingsRescan?.invalidate()
            self?.settingsRescan = nil
        }
        statusItem.onToggle = { controller.toggle() }
        statusItem.onShowSettings = { settingsWindow.show() }

        self.statusItem = statusItem
        self.controller = controller
        clockClicks = ClockClicks(concealer: concealer)
        self.settingsWindow = settingsWindow
        controller.start()

        // The first launch opens Settings, since nothing is hidden until tiers are picked.
        let firstLaunchKey = "hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            settingsWindow.show()
        }
    }

    /// Opening the app again from Finder or Spotlight brings up Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // macOS drops the restriction with the process anyway; this just doesn't wait for it.
        concealer.apply(nil)
    }

    private var anotherInstanceIsRunning: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0 != .current }
    }
}
