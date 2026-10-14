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
    ///   - defaultTier: the tier of an app that has none yet.
    ///   - running: the bundle ids of the apps running now.
    ///   - ownBundleID: this app, which always keeps its chevron.
    ///   - revealed: whether the chevron's section is open.
    public static func make(
        tiers: [String: Tier],
        defaultTier: Tier,
        running: Set<String>,
        ownBundleID: String?,
        revealed: Bool
    ) -> VisibilityPlan? {
        func isHidden(_ bundleID: String) -> Bool {
            bundleID != ownBundleID && (tiers[bundleID] ?? defaultTier).isHidden(revealed: revealed)
        }
        guard running.contains(where: isHidden) else { return nil }

        // Apps that aren't running yet are listed too, so a visible one shows
        // its icon the moment it starts instead of after the next rebuild.
        var allowed = running.union(tiers.keys).filter { !isHidden($0) }
        if let ownBundleID { allowed.insert(ownBundleID) }
        return VisibilityPlan(allowedBundleIDs: allowed.sorted(), allowedSystemItems: allSystemItems)
    }
}
