import AppKit
import Combine
import MenubarCore
import ServiceManagement

/// Which build this is. `scripts/dev.sh` runs a second copy, told apart by
/// its bundle id.
enum AppVariant {
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    static let name = isDev ? "Menubar Dev" : "Menubar"
}

/// An app that has had an icon in the menu bar, remembered so its tier can be
/// set while it isn't running.
struct KnownApp: Codable, Equatable, Identifiable {
    let bundleID: String
    var name: String
    var id: String { bundleID }
}

final class AppSettings: ObservableObject {
    /// The tier set for each app, by bundle id. An app without one gets `newAppTier`.
    @Published var tiers: [String: Tier] { didSet { save(tiers, forKey: Key.tiers) } }
    @Published var knownApps: [KnownApp] { didSet { save(knownApps, forKey: Key.knownApps) } }
    /// Where an icon goes the first time it's seen.
    @Published var newAppTier: Tier { didSet { defaults.set(newAppTier.rawValue, forKey: Key.newAppTier) } }
    /// Seconds before the chevron's section closes by itself; 0 keeps it open.
    @Published var rehideDelay: Double { didSet { defaults.set(rehideDelay, forKey: Key.rehideDelay) } }

    static let rehideChoices: [Double] = [5, 10, 30, 60, 0]

    private let defaults: UserDefaults

    private enum Key {
        static let tiers = "tiers"
        static let knownApps = "knownApps"
        static let newAppTier = "newAppTier"
        static let rehideDelay = "rehideDelay"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tiers = Self.load([String: Tier].self, from: defaults, key: Key.tiers) ?? [:]
        knownApps = Self.load([KnownApp].self, from: defaults, key: Key.knownApps) ?? []
        newAppTier = defaults.string(forKey: Key.newAppTier).flatMap(Tier.init) ?? .visible
        rehideDelay = defaults.object(forKey: Key.rehideDelay) as? Double ?? 10
    }

    func tier(of bundleID: String) -> Tier {
        tiers[bundleID] ?? newAppTier
    }

    /// Adds apps seen with menu bar icons for the first time, and keeps names
    /// up to date. Their tier stays unset, so they follow `newAppTier` until
    /// one is picked.
    func remember(_ apps: [KnownApp]) {
        var known = knownApps
        for app in apps {
            if let index = known.firstIndex(where: { $0.bundleID == app.bundleID }) {
                if known[index].name != app.name { known[index].name = app.name }
            } else {
                known.append(app)
            }
        }
        if known != knownApps { knownApps = known }
    }

    func forget(_ bundleID: String) {
        knownApps.removeAll { $0.bundleID == bundleID }
        tiers[bundleID] = nil
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// "Open at login", which only exists for the installed bundle.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
