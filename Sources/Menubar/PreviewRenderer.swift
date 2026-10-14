import AppKit
import MenubarCore
import SwiftUI

/// Draws the Settings window and the app icon to PNG files, so the design
/// can be checked, and the icon built, without opening a window.
///
///     swift run Menubar --render-previews /tmp/menubar-previews
enum PreviewRenderer {
    static func renderPreviews(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Throwaway defaults: previews must not read or touch the real tiers.
        let suite = "dev.fabio.menubar.previews"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = AppSettings(defaults: defaults)
        // Apps on this Mac, so the rows carry real icons; tiers spread over all three.
        let sample = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .accessory && $0.bundleIdentifier?.hasPrefix("com.apple.") == false }
            .prefix(7)
            .map { KnownApp(bundleID: $0.bundleIdentifier!, name: MenuBarInventory.name(of: $0)) }
        settings.knownApps = Array(sample) + [KnownApp(bundleID: "com.example.notrunning", name: "An app that has quit")]
        for (index, app) in settings.knownApps.enumerated() {
            settings.tiers[app.bundleID] = Tier.allCases[index % 3]
        }

        // All but the last two are in the menu bar now.
        let present = settings.knownApps.dropLast(2).map { MenuBarInventory.Entry(bundleID: $0.bundleID, name: $0.name) }

        for dark in [true, false] {
            let suffix = dark ? "dark" : "light"
            for problem in [nil, Concealer.Problem.otherManager(name: "Bartender 7", bundleID: "com.surteesstudios.Bartender")] {
                let concealer = Concealer(previewProblem: problem)
                // The notice version also shows the Accessibility notice.
                let inventory = MenuBarInventory(previewEntries: present, trusted: problem == nil)
                let view = SettingsView(
                    settings: settings, inventory: inventory, hiding: concealer, updates: UpdateService()
                )
                let name = problem == nil ? "settings-\(suffix).png" : "settings-notice-\(suffix).png"
                snapshot(view, size: SettingsWindowController.size, dark: dark, to: directory.appendingPathComponent(name))
                if problem == nil {
                    // The whole page, which scrolls inside the real window.
                    let full = NSSize(width: SettingsWindowController.size.width, height: 1000)
                    snapshot(view, size: full, dark: dark, to: directory.appendingPathComponent("settings-full-\(suffix).png"))
                }
            }
        }
        UserDefaults().removePersistentDomain(forName: suite)
        print("Previews written to \(directory.path)")
    }

    // MARK: - Settings

    private static func snapshot<Content: View>(_ view: Content, size: NSSize, dark: Bool, to url: URL) {
        if let rep = render(view, size: size, dark: dark) { write(rep, to: url) }
    }

    private static func render<Content: View>(_ view: Content, size: NSSize, dark: Bool) -> NSBitmapImageRep? {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        // Never ordered on screen; the window only gives the view an appearance
        // and something to lay out in.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    // MARK: - Icon

    /// Writes an .iconset folder for `iconutil -c icns`.
    static func renderIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(points * scale)
                let rep = bitmap(width: pixels, height: pixels, scale: 1) {
                    drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                }
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                write(rep, to: directory.appendingPathComponent(name))
            }
        }
    }

    /// A strip of menu bar across a dark plate: three icons, the last two
    /// fading, with a chevron at their side. Drawn on a 1024 grid.
    private static func drawIcon(in rect: NSRect) {
        let unit = rect.width / 1024
        let plate = NSBezierPath(
            roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit),
            xRadius: 185 * unit, yRadius: 185 * unit
        )
        NSGradient(
            starting: NSColor(srgbRed: 0.20, green: 0.24, blue: 0.36, alpha: 1),
            ending: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.15, alpha: 1)
        )?.draw(in: plate, angle: -90)

        let bar = NSRect(x: 180 * unit, y: 432 * unit, width: 664 * unit, height: 160 * unit)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 56 * unit, yRadius: 56 * unit).fill()

        for (index, alpha) in [0.95, 0.55, 0.25].enumerated() {
            let dot = NSRect(x: (250 + Double(index) * 130) * unit, y: 467 * unit, width: 90 * unit, height: 90 * unit)
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: dot, xRadius: 24 * unit, yRadius: 24 * unit).fill()
        }

        // The chevron, in the icon set's own shape. It's symmetric top to
        // bottom, so the path's top-down grid needs no flipping here.
        let chevron = path(for: .chevronLeft, in: NSRect(x: 650 * unit, y: 412 * unit, width: 200 * unit, height: 200 * unit))
        chevron.lineWidth = 28 * unit
        NSColor.white.setStroke()
        chevron.stroke()
    }

    /// One of the app's icons as a path filling `rect`.
    private static func path(for icon: Icon, in rect: NSRect) -> NSBezierPath {
        let scale = min(rect.width, rect.height) / Icon.gridSize
        let path = NSBezierPath()
        func point(_ x: Double, _ y: Double) -> NSPoint {
            NSPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        for command in icon.commands.joined() {
            switch command {
            case .move(let x, let y): path.move(to: point(x, y))
            case .line(let x, let y): path.line(to: point(x, y))
            case .curve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.curve(to: point(x, y), controlPoint1: point(c1x, c1y), controlPoint2: point(c2x, c2y))
            case .close: path.close()
            }
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    private static func bitmap(width: CGFloat, height: CGFloat, scale: CGFloat, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
