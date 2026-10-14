import AppKit
import ApplicationServices

/// A click on empty menu bar space on the right half of a screen opens or
/// closes the On click section. Clicks on icons and on app menus go where
/// they always went.
///
/// Telling empty space from an icon takes Accessibility: the frames of the
/// icons showing now, from each app's own tree and from MenuBarAgent's
/// (Apple's items), and the frontmost app's menus. Hidden icons keep their
/// old frames in their app's tree, so only apps the current plan shows are
/// asked. Without Accessibility nothing is watched, and `MenuBarController`
/// keeps the On click icons showing so they stay reachable.
final class BarClicks {
    var onClick: (() -> Void)?

    private let concealer: Concealer
    private var monitor: Any?
    /// Accessibility lookups run here, in click order, never on the main thread.
    private let queue = DispatchQueue(label: "dev.fabio.menubar.bar-clicks", qos: .userInteractive)
    /// Where the current click began, when that was on empty space. Only
    /// touched on `queue`.
    private var emptyClickStart: CGPoint?
    /// How far the pointer may move between press and release for a click.
    private static let clickTolerance: CGFloat = 4

    init(concealer: Concealer) {
        self.concealer = concealer
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) {
        guard let location = event.cgEvent?.location else { return }
        switch event.type {
        case .leftMouseDown:
            // ⌘-drag rearranges the bar, ⌃-click is a right click. A click
            // that closes an open menu is only closing it.
            guard AXIsProcessTrusted(),
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  Self.isOnRightHalfOfMenuBar(location), !Self.isMenuOpen else {
                queue.async { self.emptyClickStart = nil }
                return
            }
            let shown = shownApps()
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            queue.async { [weak self] in
                let empty = Self.isEmptySpace(location, apps: shown, frontmost: frontmost)
                self?.emptyClickStart = empty ? location : nil
            }
        case .leftMouseUp:
            queue.async { [weak self] in
                guard let self, let start = emptyClickStart else { return }
                emptyClickStart = nil
                guard hypot(location.x - start.x, location.y - start.y) < Self.clickTolerance else { return }
                DispatchQueue.main.async { self.onClick?() }
            }
        default:
            break
        }
    }

    /// Apps that may have icons on screen now: running, able to have UI, and
    /// not hidden by the current restriction.
    private func shownApps() -> [pid_t] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, !app.isTerminated, app.activationPolicy != .prohibited,
                  app.bundleURL?.pathExtension == "app", concealer.isShowing(bundleID) else { return nil }
            return app.processIdentifier
        }
    }

    private static func isEmptySpace(_ location: CGPoint, apps: [pid_t], frontmost: pid_t?) -> Bool {
        let hit: (CGRect) -> Bool = { $0.insetBy(dx: -2, dy: -2).contains(location) }
        if let frontmost, AX.appMenuFrames(pid: frontmost).contains(where: hit) { return false }
        if AX.systemItemFrames().contains(where: hit) { return false }
        // Side by side, so one slow app costs its own timeout and no more.
        var onIcon = [Bool](repeating: false, count: apps.count)
        onIcon.withUnsafeMutableBufferPointer { results in
            DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                results[index] = AX.menuBarItemFrames(pid: apps[index], timeout: 0.1)?.contains(where: hit) == true
            }
        }
        return !onIcon.contains(true)
    }

    /// `location` is in global display coordinates with a top-left origin, as
    /// CGEvent and Accessibility use.
    private static func isOnRightHalfOfMenuBar(_ location: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return false }
        return NSScreen.screens.contains { screen in
            let top = primaryHeight - screen.frame.maxY
            let height = max(
                screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness
            )
            return location.x >= screen.frame.midX && location.x <= screen.frame.maxX
                && location.y >= top && location.y <= top + height
        }
    }

    private static var isMenuOpen: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { $0[kCGWindowLayer as String] as? Int == menuLevel }
    }
}
