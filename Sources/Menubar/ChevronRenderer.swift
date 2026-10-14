import AppKit
import MenubarCore

/// Draws the chevron in the menu bar: pointing left while the section is
/// closed (there is more), right while it's open.
enum ChevronRenderer {
    static let size = NSSize(width: 18, height: 18)

    /// - Parameter devMarker: adds an orange dot, so the dev build can be told
    ///   apart from the installed one. A template image can't carry colour, so
    ///   that image is drawn for the menu bar's current look instead.
    static func image(revealed: Bool, devMarker: Bool, darkMenuBar: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let ink: NSColor = devMarker ? (darkMenuBar ? .white : .black) : .black
            ink.setStroke()
            path(for: revealed ? .chevronRight : .chevronLeft, in: rect.insetBy(dx: 1, dy: 1)).stroke()
            if devMarker {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = !devMarker
        image.accessibilityDescription = revealed ? "Hide menu bar icons" : "Show hidden menu bar icons"
        return image
    }

    /// One of the app's icons as a path filling `rect`, stroked at the icon
    /// set's weight for that size.
    static func path(for icon: Icon, in rect: NSRect) -> NSBezierPath {
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
        // A touch heavier than the grid weight, to match the system's icons at this size.
        path.lineWidth = Icon.strokeWidth * scale * 1.25
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}
