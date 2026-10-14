import AppKit
import Combine
import MenubarCore

/// Decides what the menu bar shows and keeps macOS told: on every tier
/// change, chevron click, app launch or quit, and wake. Also closes the
/// chevron's section again once the menu bar has been left alone.
final class MenuBarController {
    private let settings: AppSettings
    private let concealer: Concealer
    private let inventory: MenuBarInventory
    private let statusItem: StatusItemController

    private(set) var revealed = false
    private var lastActivity = Date()
    private var rehideTimer: Timer?
    private var rescanWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    init(settings: AppSettings, concealer: Concealer, inventory: MenuBarInventory, statusItem: StatusItemController) {
        self.settings = settings
        self.concealer = concealer
        self.inventory = inventory
        self.statusItem = statusItem

        // objectWillChange fires before the new value lands, so apply on the next turn.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &subscriptions)
        inventory.$entries
            .sink { [weak settings] entries in
                settings?.remember(entries.map { KnownApp(bundleID: $0.bundleID, name: $0.name) })
            }
            .store(in: &subscriptions)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Straight away, so a hidden app's icon never gets a moment on
                // screen and a visible one isn't kept off it.
                self?.apply()
                // An app adds its icon a little after it starts.
                self?.scheduleRescan(after: 3)
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply(force: true)
        })
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func start() {
        apply()
        inventory.scan()
    }

    func toggle() {
        setRevealed(!revealed)
    }

    func setRevealed(_ revealed: Bool) {
        guard revealed != self.revealed else { return }
        self.revealed = revealed
        lastActivity = Date()
        statusItem.setRevealed(revealed)
        apply()
        rehideTimer?.invalidate()
        rehideTimer = nil
        if revealed {
            rehideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkRehide()
            }
        }
    }

    /// Works out the plan for now and hands it to macOS.
    /// - Parameter force: re-sends it even when unchanged, for after a wake.
    func apply(force: Bool = false) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let plan = VisibilityPlan.make(
            tiers: settings.tiers,
            defaultTier: settings.newAppTier,
            running: running,
            ownBundleID: Bundle.main.bundleIdentifier,
            revealed: revealed
        )
        concealer.apply(plan, force: force)
    }

    func scheduleRescan(after seconds: TimeInterval) {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.inventory.scan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Hiding again

    private func checkRehide() {
        guard revealed else { return }
        if menuBarInUse() {
            lastActivity = Date()
            return
        }
        let delay = settings.rehideDelay
        if delay > 0, Date().timeIntervalSince(lastActivity) >= delay {
            setRevealed(false)
        }
    }

    /// The pointer is in the menu bar, or a menu is open, or one of the
    /// revealed apps shows a popover: hiding its icon now would pull the
    /// ground out from under it.
    private func menuBarInUse() -> Bool {
        let pointer = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let height = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
            let band = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            if band.contains(pointer) { return true }
        }

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let revealedApps = Set(settings.tiers.filter { $0.value == .onClick }.keys)
        for window in windows {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if layer == menuLevel { return true }
            // Popovers sit at the status level or above; overlays far above it
            // (dictation, screen dimmers) stay on screen and don't count.
            guard layer >= statusLevel, layer < 1000,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { continue }
            if revealedApps.contains(bundleID) || (settings.tiers[bundleID] == nil && settings.newAppTier == .onClick) {
                return true
            }
        }
        return false
    }
}
