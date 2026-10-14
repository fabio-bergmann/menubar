import MenubarCore
import XCTest

final class VisibilityPlanTests: XCTestCase {
    private let own = "dev.fabio.menubar"

    private func plan(
        _ tiers: [String: Tier],
        running: Set<String>,
        defaultTier: Tier = .visible,
        revealed: Bool = false
    ) -> VisibilityPlan? {
        VisibilityPlan.make(tiers: tiers, defaultTier: defaultTier, running: running, ownBundleID: own, revealed: revealed)
    }

    func testNothingToHideHoldsNoRestriction() {
        XCTAssertNil(plan([:], running: ["a", "b"]))
        XCTAssertNil(plan(["a": .visible], running: ["a", "b"]))
    }

    func testCollapsedHidesOnClickAndNever() {
        let result = plan(["a": .visible, "b": .onClick, "c": .never], running: ["a", "b", "c", "d"])
        XCTAssertEqual(result?.allowedBundleIDs, ["a", "d", own])
    }

    func testRevealedShowsOnClickButNotNever() {
        let result = plan(["a": .visible, "b": .onClick, "c": .never], running: ["a", "b", "c"], revealed: true)
        XCTAssertEqual(result?.allowedBundleIDs, ["a", "b", own])
    }

    func testRevealedWithOnlyOnClickAppsDropsTheRestriction() {
        XCTAssertNil(plan(["b": .onClick], running: ["a", "b"], revealed: true))
    }

    func testHiddenAppsThatAreNotRunningNeedNoRestriction() {
        XCTAssertNil(plan(["b": .never, "c": .onClick], running: ["a"]))
    }

    func testVisibleAppsThatAreNotRunningAreAllowedAhead() {
        let result = plan(["a": .visible, "b": .never], running: ["b"])
        XCTAssertEqual(result?.allowedBundleIDs, ["a", own])
    }

    func testDefaultTierAppliesToAppsWithoutOne() {
        let result = plan(["a": .visible], running: ["a", "new"], defaultTier: .onClick)
        XCTAssertEqual(result?.allowedBundleIDs, ["a", own])
    }

    func testAppleAppsWithoutATierIgnoreTheDefault() {
        // SystemUIServer hosts Siri and Time Machine and is never listed.
        XCTAssertNil(plan([:], running: ["com.apple.systemuiserver"], defaultTier: .never))
        let result = plan(["b": .never], running: ["com.apple.systemuiserver", "b"], defaultTier: .onClick)
        XCTAssertEqual(result?.allowedBundleIDs, ["com.apple.systemuiserver", own])
    }

    func testAppleAppsWithATierFollowIt() {
        let result = plan(["com.apple.weather": .never], running: ["com.apple.weather"])
        XCTAssertEqual(result?.allowedBundleIDs, [own])
    }

    func testBackgroundOnlyAppsIgnoreTheDefault() {
        XCTAssertNil(VisibilityPlan.make(
            tiers: [:], defaultTier: .onClick, running: ["helper"], backgroundOnly: ["helper"],
            ownBundleID: own, revealed: false
        ))
    }

    func testAppsSeenEarlierStayOnTheList() {
        let before = VisibilityPlan.make(
            tiers: ["b": .never], defaultTier: .visible, running: ["a", "b"], seen: ["a", "b"],
            ownBundleID: own, revealed: false
        )
        let afterAQuit = VisibilityPlan.make(
            tiers: ["b": .never], defaultTier: .visible, running: ["b"], seen: ["a", "b"],
            ownBundleID: own, revealed: false
        )
        XCTAssertEqual(before, afterAQuit)
        // Nothing hidden running: still no restriction, whatever ran before.
        XCTAssertNil(VisibilityPlan.make(
            tiers: ["b": .never], defaultTier: .visible, running: ["a"], seen: ["a", "b"],
            ownBundleID: own, revealed: false
        ))
    }

    func testOwnChevronIsNeverHidden() {
        let result = plan([own: .never, "b": .never], running: [own, "b"])
        XCTAssertEqual(result?.allowedBundleIDs, [own])
        XCTAssertNil(plan([own: .never], running: [own]))
    }

    func testAppleItemsStayAllowed() {
        let result = plan(["b": .never], running: ["b"])
        XCTAssertEqual(result?.allowedSystemItems, VisibilityPlan.allSystemItems)
    }
}
