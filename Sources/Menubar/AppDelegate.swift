import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let inventory = MenuBarInventory()
    private let concealer = Concealer()
    private let updates = UpdateService()
    private var clockClicks: ClockClicks?
    private var barClicks: BarClicks?
    private var controller: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var settingsRescan: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning {
            NSApp.terminate(nil)
            return
        }

        let controller = MenuBarController(settings: settings, concealer: concealer, inventory: inventory)
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
        let barClicks = BarClicks(concealer: concealer)
        barClicks.onClick = { controller.toggle() }

        self.controller = controller
        self.barClicks = barClicks
        clockClicks = ClockClicks(concealer: concealer)
        self.settingsWindow = settingsWindow
        controller.start()

        // There's nothing in the menu bar to open Settings from, so it opens
        // by itself the first time, since nothing is hidden until tiers are
        // picked, and whenever Accessibility is missing, which every update of
        // an ad-hoc signed app causes. Not for the dev build, which rebuilds
        // on every save.
        let firstLaunchKey = "hasLaunchedBefore"
        let firstLaunch = !UserDefaults.standard.bool(forKey: firstLaunchKey)
        UserDefaults.standard.set(true, forKey: firstLaunchKey)
        if firstLaunch || (!AXIsProcessTrusted() && !AppVariant.isDev) {
            settingsWindow.show()
        }
    }

    /// Opening the app again (Spotlight, Raycast, Finder) brings up Settings.
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
