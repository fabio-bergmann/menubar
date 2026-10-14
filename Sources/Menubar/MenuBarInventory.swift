import AppKit
import ApplicationServices

/// Which running apps have icons in the menu bar, read through Accessibility.
///
/// Only Settings needs this, to list the apps worth giving a tier. Hiding
/// itself goes by bundle id and works without it, so a lost Accessibility
/// grant (every rebuild of an ad-hoc signed app loses it) costs the list,
/// never the hiding.
final class MenuBarInventory: ObservableObject {
    struct Entry: Equatable, Identifiable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    /// The apps with menu bar icons at the last scan, by name.
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    /// Left off the list: the processes that draw the bar and host Apple's
    /// own items. Control Center's items are kept by macOS's numeric ids, and
    /// SystemUIServer hosts Siri, Time Machine, VPN and Eject as one bundle,
    /// which System Settings turns on and off item by item instead. They stay
    /// allowed, like every running app without a tier.
    static let systemHosts: Set<String> = [
        "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent",
        "com.apple.notificationcenterui", "com.apple.loginwindow",
    ]

    private let queue = DispatchQueue(label: "dev.fabio.menubar.inventory", qos: .userInitiated)
    private var scanning = false
    private var rescanRequested = false
    private let isPreview: Bool

    init() {
        isPreview = false
    }

    /// For the previews: a fixed list that scanning never replaces.
    init(previewEntries: [Entry], trusted: Bool) {
        isPreview = true
        entries = previewEntries
        isTrusted = trusted
    }

    /// Asks macOS for Accessibility afresh. Each build is signed anew, and a
    /// grant made to an earlier build stays switched on in System Settings
    /// while doing nothing. So the old entry is cleared first, and macOS's
    /// prompt then adds one for this build, ready to be switched on.
    func requestTrust() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", bundleID]
            try? reset.run()
            reset.waitUntilExit()
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func scan(completion: (([Entry]) -> Void)? = nil) {
        guard !isPreview else { return }
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            entries = Self.fallbackEntries()
            completion?(entries)
            return
        }
        guard !scanning else {
            rescanRequested = true
            return
        }
        scanning = true
        // Only .app bundles: XPC services and WebKit helpers never have menu
        // bar items, and some never answer Accessibility either.
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, Entry)? in
            guard let bundleID = app.bundleIdentifier, app != .current, !app.isTerminated,
                  app.bundleURL?.pathExtension == "app", !Self.systemHosts.contains(bundleID) else { return nil }
            return (app.processIdentifier, Entry(bundleID: bundleID, name: Self.name(of: app)))
        }
        queue.async { [weak self] in
            // Side by side, so one slow app costs its own timeout and no more.
            var hasItems = [Bool](repeating: false, count: apps.count)
            hasItems.withUnsafeMutableBufferPointer { results in
                DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                    results[index] = Self.hasMenuBarItems(pid: apps[index].0)
                }
            }
            let found = apps.indices.filter { hasItems[$0] }.map { apps[$0].1 }
            let unique = Dictionary(found.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
            let sorted = unique.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                self.entries = sorted
                completion?(sorted)
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.scan()
                }
            }
        }
    }

    /// Whether the app has an extras menu bar with anything in it: the
    /// Accessibility side of its status items. Hidden items stay in it, so
    /// this reads the same whether they're showing or not.
    private static func hasMenuBarItems(pid: pid_t) -> Bool {
        let element = AXUIElementCreateApplication(pid)
        // A busy app (a sync in progress, a hung helper) mustn't stall the scan.
        AXUIElementSetMessagingTimeout(element, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let bar = value as! AXUIElement
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(bar, kAXChildrenAttribute as CFString, &count) == .success else {
            return false
        }
        return count > 0
    }

    /// Without Accessibility: apps that run without a Dock icon, which are
    /// nearly always menu bar apps. Regular apps with an icon go unlisted.
    private static func fallbackEntries() -> [Entry] {
        let entries = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .accessory && $0 != .current }
            .compactMap { app -> Entry? in
                guard let bundleID = app.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else { return nil }
                return Entry(bundleID: bundleID, name: name(of: app))
            }
        // Two copies of one app are one row.
        return Dictionary(entries.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first }).values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func name(of app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? app.bundleIdentifier ?? "Unknown"
    }

    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = running.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
