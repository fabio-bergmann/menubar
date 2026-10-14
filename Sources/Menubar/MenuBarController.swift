import AppKit
import Combine
import MenubarCore

/// Decides what the menu bar shows and keeps macOS told: on every tier
/// change, click on empty menu bar space, app launch or quit, wake and display
/// change. Also closes the On click section again once the menu bar has been
/// left alone.
final class MenuBarController {
    private let settings: AppSettings
    private let concealer: Concealer
    private let inventory: MenuBarInventory

    private(set) var revealed = false
    /// Nothing is hidden until a second after launch (see `start`).
    private var started = false
    private var lastActivity = Date()
    private var rehideTimer: Timer?
    private var rescanWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var runningObservation: NSKeyValueObservation?
    private var runningPIDs = Set<pid_t>()
    /// Every app seen running since launch, and which of those can't have UI.
    private var seenApps = Set<String>()
    private var seenBackgroundOnly = Set<String>()
    private var newcomers = Set<pid_t>()
    private var newcomerCheck: DispatchWorkItem?
    private var adopting = false

    init(settings: AppSettings, concealer: Concealer, inventory: MenuBarInventory) {
        self.settings = settings
        self.concealer = concealer
        self.inventory = inventory

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

        // Every app that starts or quits, background agents included (those
        // don't all post the launch notifications).
        // The change only carries the apps that came or went, so the whole
        // list is read again each time.
        runningObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.runningAppsChanged() }
        }
        runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply(force: true)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.apply(force: true)
        })
        // Posted when any app's Accessibility switch changes; the new state
        // takes a moment to read back.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.apply()
                self?.inventory.scan()
            }
        })
    }

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
    }

    /// Waits a second before the first restriction, so the menu bar has
    /// settled after login: macOS may park an icon that arrives while one is
    /// held.
    func start() {
        inventory.scan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.started = true
            self?.apply()
        }
    }

    func toggle() {
        setRevealed(!revealed)
    }

    func setRevealed(_ revealed: Bool) {
        guard revealed != self.revealed else { return }
        self.revealed = revealed
        lastActivity = Date()
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
        guard started else { return }
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap(\.bundleIdentifier))
        // A bundle id counts as background-only when no running copy may have UI.
        let withUI = Set(apps.filter { $0.activationPolicy != .prohibited }.compactMap(\.bundleIdentifier))
        seenApps.formUnion(running)
        seenBackgroundOnly = seenBackgroundOnly.union(running.subtracting(withUI)).subtracting(withUI)
        let plan = VisibilityPlan.make(
            tiers: settings.tiers,
            defaultTier: settings.newAppTier,
            running: running,
            seen: seenApps,
            backgroundOnly: seenBackgroundOnly,
            ownBundleID: Bundle.main.bundleIdentifier,
            // Without Accessibility a click on the menu bar can't be told
            // from a click on an icon, so On click icons would be out of reach.
            revealed: revealed || !AXIsProcessTrusted()
        )
        concealer.apply(plan, force: force)
    }

    func scheduleRescan(after seconds: TimeInterval) {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.inventory.scan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func runningAppsChanged() {
        let apps = NSWorkspace.shared.runningApplications
        let pids = Set(apps.map(\.processIdentifier))
        let started = apps.filter { !runningPIDs.contains($0.processIdentifier) }
        runningPIDs = pids
        // Straight away, so a hidden app's icon never gets a moment on screen
        // and a visible one isn't kept off it.
        apply()
        // An app adds its icon a little after it starts.
        scheduleRescan(after: 3)
        watchNewcomers(started)
    }

    // MARK: - Newly started apps

    /// macOS can park the icon of an app that starts while icons are hidden
    /// (off screen, no width), even when the app is allowed, until a moment
    /// with no restriction at all. Pelmet saw this; others saw icons land
    /// fine. So a little after a visible app starts its icons are looked at,
    /// and if one is parked the restriction is lifted until it lands, for 2.5
    /// seconds at most. Needs Accessibility to look; without it nothing is done.
    private func watchNewcomers(_ apps: [NSRunningApplication]) {
        let shown = apps.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return !settings.tier(of: bundleID).isHidden(revealed: revealed)
        }
        guard !shown.isEmpty else { return }
        newcomers.formUnion(shown.map(\.processIdentifier))
        newcomerCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkNewcomers() }
        newcomerCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func checkNewcomers() {
        let pids = newcomers
        newcomers = []
        guard concealer.isHolding, !adopting, AXIsProcessTrusted() else { return }
        let screens = Self.displayBounds()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let parked = pids.filter { Self.hasParkedItem(pid: $0, screens: screens) }
            guard !parked.isEmpty else { return }
            DispatchQueue.main.async { self?.adopt(parked, screens: screens) }
        }
    }

    private func adopt(_ pids: Set<pid_t>, screens: [CGRect]) {
        guard concealer.isHolding, !adopting else { return }
        adopting = true
        NSLog("Menubar: lifting until \(pids.count) new app(s) get their icons on screen")
        concealer.lift()
        let deadline = Date().addingTimeInterval(2.5)
        func poll() {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) { [weak self] in
                let parked = pids.contains { Self.hasParkedItem(pid: $0, screens: screens) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if parked, Date() < deadline {
                        poll()
                    } else {
                        self.adopting = false
                        self.concealer.reassert()
                    }
                }
            }
        }
        poll()
    }

    /// An icon macOS hasn't placed: no width, or on no display.
    private static func hasParkedItem(pid: pid_t, screens: [CGRect]) -> Bool {
        guard let frames = AX.menuBarItemFrames(pid: pid) else { return false }
        return frames.contains { frame in
            frame.width < 4 || !screens.contains { $0.intersects(frame) }
        }
    }

    /// Every display, in the top-left-origin coordinates Accessibility uses.
    private static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    // MARK: - Hiding again

    private func checkRehide() {
        // "Never" keeps them showing until the menu bar is clicked again.
        guard revealed, settings.rehideDelay > 0 else { return }
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
