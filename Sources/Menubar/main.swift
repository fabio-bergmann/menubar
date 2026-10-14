import AppKit

// Developer entry points: draw the UI or the app icon to PNG files and exit,
// without putting anything on screen.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--render-previews"), arguments.count > flag + 1 {
    _ = NSApplication.shared
    PreviewRenderer.renderPreviews(to: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
if let flag = arguments.firstIndex(of: "--render-icon"), arguments.count > flag + 1 {
    PreviewRenderer.renderIconSet(to: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
// Hides one app's icons for a few seconds and reports what macOS said, to
// check the restriction from a terminal: --try-hiding <bundle id> [seconds]
if let flag = arguments.firstIndex(of: "--try-hiding"), arguments.count > flag + 1 {
    let seconds = arguments.count > flag + 2 ? Double(arguments[flag + 2]) ?? 3 : 3
    RestrictionProbe.run(hiding: arguments[flag + 1], for: seconds)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon, no app menu.
app.setActivationPolicy(.accessory)
app.run()
