import AppKit
import MenuBarRestriction
import MenubarCore

/// `--try-hiding`: one restriction, held for a few seconds, then released by
/// exiting. Never returns.
enum RestrictionProbe {
    static func run(hiding bundleID: String, for seconds: Double) -> Never {
        print("Restriction available: \(MBRestrictionIsAvailable())")
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard let plan = VisibilityPlan.make(
            tiers: [bundleID: .never], defaultTier: .visible, running: running, ownBundleID: nil, revealed: false
        ) else {
            print("\(bundleID) isn't running, so there's nothing to hide.")
            exit(1)
        }
        let started = Date()
        MBRestrictionActivate(plan.allowedSystemItems.map(NSNumber.init), plan.allowedBundleIDs) { handle, error in
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard let handle else {
                print("Refused after \(elapsed) ms: \(error?.localizedDescription ?? "no reason given")")
                exit(1)
            }
            print("Holding after \(elapsed) ms: \(bundleID) hidden, \(plan.allowedBundleIDs.count) apps allowed")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MBRestrictionInvalidate(handle)
                print("Released")
                exit(0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            print("No answer from macOS within 10 seconds")
            exit(2)
        }
        dispatchMain()
    }
}
