import AppKit
import ApplicationServices

/// The few Accessibility reads this app makes.
enum AX {
    static func value(of element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// Global display coordinates, top-left origin.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(of: element, kAXPositionAttribute),
              let size = value(of: element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// The frames of an app's menu bar items, from its own Accessibility tree.
    /// Hidden items stay listed there, with the frame they last had on screen.
    static func menuBarItemFrames(pid: pid_t, timeout: Float = 0.25) -> [CGRect]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = value(of: app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            return nil
        }
        return children(of: bar as! AXUIElement).compactMap(frame(of:))
    }

    /// The frames of an app's own menus (File, Edit…) in the menu bar.
    static func appMenuFrames(pid: pid_t, timeout: Float = 0.25) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = value(of: app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            return []
        }
        return children(of: bar as! AXUIElement).compactMap(frame(of:))
    }

    /// The frames of Apple's items (clock, Control Center, Wi-Fi…), which
    /// MenuBarAgent hosts: bar > group > menu extra.
    static func systemItemFrames(timeout: Float = 0.25) -> [CGRect] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let bar = value(of: app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            return []
        }
        return children(of: bar as! AXUIElement).flatMap { group in
            ([group] + children(of: group)).compactMap(frame(of:))
        }
    }
}
