import AppKit
import ApplicationServices
import Combine

/// Opens Notification Center from the clock while icons are hidden.
///
/// While any app holds macOS 27's menu bar restriction, MenuBarAgent ignores
/// the clock, clicks and AXPress alike: the restriction is exam mode's, which
/// keeps notifications out of reach. So clicks on the clock are watched, and
/// the clock is pressed again with the restriction lifted for a moment.
/// Hidden icons show for under a second meanwhile; macOS keeps them up that
/// long however soon the restriction comes back.
///
/// The approach is Hidden Bar's (dwarvesf/hidden PR #453, MIT), measured there
/// on 27.0.1. It needs Accessibility, to find and press the clock.
final class ClockClicks {
    private static let agentBundleID = "com.apple.MenuBarAgent"
    private static let clockIdentifier = "com.apple.menuextra.clock"
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"
    /// Well above how long MenuBarAgent takes to answer right after a lift (40-90 ms).
    private static let messagingTimeout: Float = 0.5
    /// MenuBarAgent ignores a press that reaches it before it has applied the
    /// lift. Waiting this long before looking the clock up holds the press back
    /// until it has.
    private static let liftDelay: TimeInterval = 0.03

    private let concealer: Concealer
    private var monitor: Any?
    private var subscription: AnyCancellable?
    private var pressing = false
    /// Accessibility lookups run here, in click order, never on the main thread.
    private let queue = DispatchQueue(label: "dev.fabio.menubar.clock", qos: .userInteractive)
    /// The clock's frame when the current click began on it with Notification
    /// Center closed. Only touched on `queue`.
    private var clickedClock: CGRect?

    init(concealer: Concealer) {
        self.concealer = concealer
        // Clicks are only watched while icons are hidden.
        subscription = concealer.$isHolding
            .removeDuplicates()
            .sink { [weak self] holding in self?.setWatching(holding) }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func setWatching(_ watching: Bool) {
        if watching, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.handle(event)
            }
        } else if !watching, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Notification Center is checked when the click begins: a click on the
    /// clock closes an open panel by itself, restricted or not, and pressing
    /// the clock too would open it again. The press waits for the click to end.
    private func handle(_ event: NSEvent) {
        guard !pressing, AXIsProcessTrusted(), let location = event.cgEvent?.location else { return }
        switch event.type {
        case .leftMouseDown:
            // ⌘-drag rearranges the bar and ⌃-click is a right click.
            let plain = event.modifierFlags.isDisjoint(with: [.command, .control])
            let inMenuBar = Self.isInMenuBar(location)
            // NSScreen is the main thread's; the lookup below isn't.
            let panelHeight = (NSScreen.screens.map(\.frame.height).min() ?? 0) / 2
            queue.async { [weak self] in
                guard let self else { return }
                guard plain, inMenuBar, !Self.isNotificationCenterOpen(minimumHeight: panelHeight),
                      let clock = Self.clocks().first(where: { $0.frame.contains(location) }) else {
                    clickedClock = nil
                    return
                }
                clickedClock = clock.frame
            }
        case .leftMouseUp:
            queue.async { [weak self] in
                guard let self else { return }
                defer { clickedClock = nil }
                guard clickedClock?.contains(location) == true else { return }
                DispatchQueue.main.async { self.press(at: location) }
            }
        default:
            break
        }
    }

    private func press(at location: CGPoint) {
        guard concealer.isHolding, !pressing else { return }
        pressing = true
        concealer.lift()
        queue.asyncAfter(deadline: .now() + Self.liftDelay) { [weak self] in
            // Looked up afresh: the element from before the lift may be stale.
            let clocks = Self.clocks()
            if let clock = clocks.first(where: { $0.frame.contains(location) }) ?? clocks.first {
                AXUIElementPerformAction(clock.element, kAXPressAction as CFString)
            }
            DispatchQueue.main.async {
                // Notification Center stays open once the icons are hidden again.
                self?.concealer.reassert()
                self?.pressing = false
            }
        }
    }

    /// Keeps the Accessibility lookups to clicks in a menu bar. `location` is in
    /// global display coordinates with a top-left origin, as CGEvent and
    /// Accessibility use.
    private static func isInMenuBar(_ location: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return false }
        return NSScreen.screens.contains { screen in
            let top = primaryHeight - screen.frame.maxY
            let height = max(
                screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness
            )
            return location.x >= screen.frame.minX && location.x <= screen.frame.maxX
                && location.y >= top && location.y <= top + height
        }
    }

    /// Every clock (one per display with a menu bar). MenuBarAgent hosts each
    /// item in a group: bar > group > menu extra.
    private static func clocks() -> [(element: AXUIElement, frame: CGRect)] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first else {
            return []
        }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let bar = AX.value(of: app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            return []
        }
        var clocks: [(element: AXUIElement, frame: CGRect)] = []
        for group in AX.children(of: bar as! AXUIElement) {
            for item in [group] + AX.children(of: group)
            where AX.value(of: item, "AXIdentifier") as? String == clockIdentifier {
                if let frame = AX.frame(of: item) { clocks.append((item, frame)) }
            }
        }
        return clocks
    }

    /// The panel is a window as tall as the screen; banners are a few rows
    /// tall and desktop widgets sit below the desktop. Owner, layer and bounds
    /// need no Screen Recording permission, unlike window names.
    /// - Parameter minimumHeight: half the shortest screen's height.
    private static func isNotificationCenterOpen(minimumHeight: CGFloat) -> Bool {
        let owners = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: notificationCenterBundleID).map(\.processIdentifier)
        )
        guard !owners.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.height >= minimumHeight
        }
    }
}
