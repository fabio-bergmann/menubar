import Foundation

/// What macOS is asked to show. macOS 27 hides menu bar icons from an
/// allowlist: every app named here keeps its icons, every other app's are
/// hidden. So hiding an app means leaving it off the list, and an app that
/// starts later is hidden until the list is rebuilt with it on.
public struct VisibilityPlan: Equatable, Sendable {
    /// Sorted, so two plans for the same state compare equal.
    public var allowedBundleIDs: [String]
    /// macOS's own items (clock, Wi-Fi, Control Center…) by their numeric ids.
    public var allowedSystemItems: [Int]

    public init(allowedBundleIDs: [String], allowedSystemItems: [Int]) {
        self.allowedBundleIDs = allowedBundleIDs
        self.allowedSystemItems = allowedSystemItems
    }

    /// The ids macOS numbers its own items with. Ids a Mac doesn't have are
    /// ignored, so keeping the whole range keeps every Apple item.
    public static let allSystemItems = Array(0..<64)

    /// The plan for the current state, or nil when nothing running has to be
    /// hidden, in which case no restriction is held at all.
    ///
    /// - Parameters:
    ///   - tiers: the tier set for each app, by bundle id.
    ///   - defaultTier: the tier of an app that has none yet, such as one that
    ///     just started and hasn't been looked at. Apple's own apps and
    ///     `backgroundOnly` ones are left out of it and stay allowed until given
    ///     a tier: some of Apple's never appear in the list (SystemUIServer
    ///     hosts Siri, Time Machine and VPN), and hiding an app that can't have
    ///     icons would only hold a restriction for nothing.
    ///   - running: the bundle ids of the apps running now.
    ///   - seen: apps that ran earlier. They stay on the list, so an app that
    ///     quits and starts again leaves the plan alone: every new plan costs
    ///     a connection to MenuBarAgent that macOS keeps until this app quits.
    ///   - backgroundOnly: apps that can't have menu bar icons.
    ///   - ownBundleID: this app, which is never hidden.
    ///   - revealed: whether the On click icons are showing.
    public static func make(
        tiers: [String: Tier],
        defaultTier: Tier,
        running: Set<String>,
        seen: Set<String> = [],
        backgroundOnly: Set<String> = [],
        ownBundleID: String?,
        revealed: Bool
    ) -> VisibilityPlan? {
        func isHidden(_ bundleID: String) -> Bool {
            if bundleID == ownBundleID { return false }
            if let tier = tiers[bundleID] { return tier.isHidden(revealed: revealed) }
            if bundleID.hasPrefix("com.apple.") || backgroundOnly.contains(bundleID) { return false }
            return defaultTier.isHidden(revealed: revealed)
        }
        guard running.contains(where: isHidden) else { return nil }

        // Apps that aren't running yet are listed too, so a visible one shows
        // its icon the moment it starts instead of after the next rebuild.
        var allowed = running.union(seen).union(tiers.keys).filter { !isHidden($0) }
        if let ownBundleID { allowed.insert(ownBundleID) }
        return VisibilityPlan(allowedBundleIDs: allowed.sorted(), allowedSystemItems: allSystemItems)
    }
}
