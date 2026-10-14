// swift-tools-version: 5.9
import PackageDescription

// No package dependencies on purpose: the .app is assembled by hand
// (scripts/build-app.sh), and SwiftPM resource bundles from dependencies
// don't land where a hand-built bundle looks for them.
let package = Package(
    name: "Menubar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MenubarCore"),
        // The private macOS API, in Objective-C so its exceptions can be caught.
        .target(name: "MenuBarRestriction"),
        .executableTarget(name: "Menubar", dependencies: ["MenubarCore", "MenuBarRestriction"]),
        .testTarget(name: "MenubarCoreTests", dependencies: ["MenubarCore"]),
    ]
)
