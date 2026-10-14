import AppKit
import MenuBarRestriction
import MenubarCore

/// Holds macOS's menu bar restriction for the current plan, and says so when
/// it can't. Fails open: whenever a restriction can't be held, none is, so
/// every icon shows rather than the wrong ones hiding.
final class Concealer: ObservableObject {
    enum Problem: Equatable {
        /// This macOS doesn't have the restriction (before 27, or Apple moved it).
        case unavailable
        /// macOS turned the restriction down; everything shows meanwhile.
        case failed(String)
        /// Another menu bar manager is running, and the two would undo each other.
        case otherManager(name: String, bundleID: String)

        var message: String {
            switch self {
            case .unavailable:
                "This version of macOS doesn't offer the menu bar hiding \(AppVariant.name) relies on, so every icon stays visible."
            case .failed(let reason):
                "macOS turned down the request to hide icons, so every icon is visible for now. \(reason)"
            case .otherManager(let name, _):
                "\(name) is also managing the menu bar. With both running they undo each other's hiding."
            }
        }

        var action: Action? {
            if case .otherManager(let name, let bundleID) = self { return .quit(name: name, bundleID: bundleID) }
            return nil
        }
    }

    enum Action: Equatable {
        case quit(name: String, bundleID: String)

        var title: String {
            switch self {
            case .quit(let name, _): "Quit \(name)"
            }
        }
    }

    @Published private(set) var problem: Problem?
    /// Whether macOS is hiding icons for this app right now.
    @Published private(set) var isHolding = false

    /// Menu bar managers that hide icons the same way, by bundle id. Each
    /// build of this app counts the other one too (`scripts/dev.sh`).
    private static let otherManagers: [String: String] = [
        "com.surteesstudios.Bartender": "Bartender",
        "com.jordanbaird.Ice": "Ice",
        "com.stonerl.Thaw": "Thaw",
        "app.fif7y.Pelmet": "Pelmet",
        "com.dwarvesv.minimalbar": "Hidden Bar",
        "com.dwarvesv.minimalbar.direct": "Hidden Bar",
        "dev.fabio.menubar": "Menubar",
        "dev.fabio.menubar.dev": "Menubar Dev",
    ]

    private var handle: Any? {
        didSet { if (handle != nil) != isHolding { isHolding = handle != nil } }
    }
    /// The last plan asked for; nil means no restriction.
    private var target: VisibilityPlan?
    private var failure: String?
    /// Turned-down requests in a row, for spacing out the retries.
    private var failures = 0
    private var retry: DispatchWorkItem?
    /// Bumped by every request, so a late answer to an older one is dropped.
    private var generation = 0
    /// Lifts in progress (the clock, a newly started app). While any is,
    /// new plans are only noted; the last `reassert()` puts the latest back.
    private var lifts = 0
    private var runningObservation: NSKeyValueObservation?
    private let isPreview: Bool

    init() {
        isPreview = false
        runningObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.checkForOtherManagers() }
        }
        checkForOtherManagers()
    }

    /// For the previews: shows `problem` and never touches the menu bar.
    init(previewProblem: Problem?) {
        isPreview = true
        problem = previewProblem
    }

    /// Hands macOS the plan, or drops the restriction for a nil one.
    /// - Parameter force: re-sends a plan even when it hasn't changed.
    func apply(_ plan: VisibilityPlan?, force: Bool = false) {
        guard !isPreview else { return }
        if plan == target, !force, failure == nil { return }
        target = plan
        guard lifts == 0 else { return }
        generation += 1
        let generation = generation

        guard let plan else {
            release()
            failure = nil
            updateProblem()
            return
        }
        guard MBRestrictionIsAvailable() else {
            updateProblem()
            return
        }
        NSLog("Menubar: hiding all but \(plan.allowedBundleIDs.count) apps")
        MBRestrictionActivate(plan.allowedSystemItems.map(NSNumber.init), plan.allowedBundleIDs) { [weak self] handle, error in
            guard let self, generation == self.generation else {
                if let handle { MBRestrictionInvalidate(handle) }
                return
            }
            if let handle {
                // The new one is in place before the old one goes, so the bar
                // never shows everything for a moment in between.
                let old = self.handle
                self.handle = handle
                if let old { MBRestrictionInvalidate(old) }
                self.failure = nil
                self.failures = 0
                self.retry?.cancel()
            } else {
                NSLog("Menubar: restriction refused: \(error?.localizedDescription ?? "no reason given")")
                self.release()
                self.failure = error?.localizedDescription ?? "No reason given."
                self.scheduleRetry()
            }
            self.updateProblem()
        }
    }

    /// Shows everything for a moment, keeping the plan to put back with
    /// `reassert()`. For the few things macOS refuses while icons are hidden.
    /// Every lift needs its own reassert.
    func lift() {
        guard !isPreview else { return }
        lifts += 1
        generation += 1
        release()
    }

    /// Ends a `lift()`. When it's the last one, the latest plan goes back.
    func reassert() {
        guard !isPreview, lifts > 0 else { return }
        lifts -= 1
        if lifts == 0 { apply(target, force: true) }
    }

    func perform(_ action: Action) {
        switch action {
        case .quit(_, let bundleID):
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        }
    }

    func checkForOtherManagers() {
        guard !isPreview else { return }
        updateProblem()
    }

    /// MenuBarAgent may be restarting or busy; ask again, less often over time.
    private func scheduleRetry() {
        failures += 1
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            apply(target, force: true)
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (failures < 3 ? 10 : 60), execute: work)
    }

    private func release() {
        if let handle { MBRestrictionInvalidate(handle) }
        handle = nil
    }

    private func updateProblem() {
        let next: Problem?
        if !MBRestrictionIsAvailable() {
            next = .unavailable
        } else if let other = runningOtherManager() {
            next = .otherManager(name: other.name, bundleID: other.bundleID)
        } else if let failure {
            next = .failed(failure)
        } else {
            next = nil
        }
        if next != problem { problem = next }
    }

    private func runningOtherManager() -> (name: String, bundleID: String)? {
        let own = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard let bundleID = app.bundleIdentifier, bundleID != own,
                  let name = Self.otherManagers[bundleID] else { continue }
            return (app.localizedName ?? name, bundleID)
        }
        return nil
    }
}
