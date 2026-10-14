import AppKit
import MenubarCore
import SwiftUI

/// Draws the chevron, the Settings window and the app icon to PNG files, so
/// the design can be checked, and the icon built, without opening a window.
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

        write(chevronSheet(), to: directory.appendingPathComponent("chevron.png"))
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

    // MARK: - Menu bar

    /// The chevron closed and open, on a light and a dark menu bar, at 4x.
    private static func chevronSheet() -> NSBitmapImageRep {
        let cell = NSSize(width: 44, height: 28)
        return bitmap(width: cell.width * 4, height: cell.height * 2, scale: 4) {
            for (row, dark) in [false, true].enumerated() {
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: CGFloat(row) * cell.height, width: cell.width * 4, height: cell.height).fill()
                for (column, (revealed, dev)) in [(false, false), (true, false), (false, true), (true, true)].enumerated() {
                    let image = ChevronRenderer.image(revealed: revealed, devMarker: dev, darkMenuBar: dark)
                    let origin = NSPoint(
                        x: CGFloat(column) * cell.width + (cell.width - image.size.width) / 2,
                        y: CGFloat(row) * cell.height + (cell.height - image.size.height) / 2
                    )
                    let rect = NSRect(origin: origin, size: image.size)
                    if image.isTemplate {
                        // How the menu bar tints a template image.
                        let tinted = NSImage(size: image.size, flipped: false) { bounds in
                            image.draw(in: bounds)
                            (dark ? NSColor.white : NSColor.black).set()
                            bounds.fill(using: .sourceAtop)
                            return true
                        }
                        tinted.draw(in: rect)
                    } else {
                        image.draw(in: rect)
                    }
                }
            }
        }
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
    /// fading, with the chevron at their side. Drawn on a 1024 grid.
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
        let chevron = ChevronRenderer.path(for: .chevronLeft, in: NSRect(x: 650 * unit, y: 412 * unit, width: 200 * unit, height: 200 * unit))
        chevron.lineWidth = 28 * unit
        NSColor.white.setStroke()
        chevron.stroke()
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
