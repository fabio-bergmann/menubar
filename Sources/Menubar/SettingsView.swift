import AppKit
import MenubarCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var inventory: MenuBarInventory
    @ObservedObject var hiding: Concealer
    @ObservedObject var updates: UpdateService

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    notices
                    iconsSection
                    behaviourSection
                    updatesSection
                }
                .padding(18)
            }
            Divider()
            HStack {
                Text("Click empty menu bar space on the right to show On click icons.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit \(AppVariant.name)") { NSApp.terminate(nil) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 18)
            .frame(height: 44)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Notices

    @ViewBuilder private var notices: some View {
        if let problem = hiding.problem {
            notice(problem.message, action: problem.action.map { action in
                (action.title, { hiding.perform(action) })
            })
        }
        if !inventory.isTrusted {
            notice(
                "Allow \(AppVariant.name) in Accessibility so it can tell a click on empty menu bar space "
                    + "from a click on an icon. Until then, On click icons stay visible. "
                    + "It also lists every app with a menu bar icon here and keeps the clock opening "
                    + "Notification Center while icons are hidden.",
                action: ("Allow Accessibility…", inventory.requestTrust)
            )
        }
    }

    private func notice(_ message: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(.alert, size: 16)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.0, action: action.1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Icons

    /// Apps in the menu bar now, then remembered ones that aren't, each by name.
    private var rows: [KnownApp] {
        let current = Set(inventory.entries.map(\.bundleID))
        let present = inventory.entries.map { KnownApp(bundleID: $0.bundleID, name: $0.name) }
        let absent = settings.knownApps.filter { !current.contains($0.bundleID) }
        let byName: (KnownApp, KnownApp) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return present.sorted(by: byName) + absent.sorted(by: byName)
    }

    private var iconsSection: some View {
        section("Menu bar icons") {
            let current = Set(inventory.entries.map(\.bundleID))
            if rows.isEmpty {
                Text("No apps with menu bar icons found yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider().padding(.leading, 38) }
                    AppRow(app: app, isPresent: current.contains(app.bundleID), tier: tierBinding(app.bundleID)) {
                        settings.forget(app.bundleID)
                    }
                }
            }
            Text("Each app's icons move together; macOS hides menu bar icons per app. "
                + "Apple's own icons (clock, Wi-Fi, Battery, Sound…) are set in System Settings › Control Center. "
                + "While icons are hidden, macOS also hides Now Playing, Focus and the camera and microphone indicator "
                + "(the coloured dot stays).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tierBinding(_ bundleID: String) -> Binding<Tier> {
        Binding(
            get: { settings.tier(of: bundleID) },
            set: { settings.tiers[bundleID] = $0 }
        )
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        section("Behaviour") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("New icons")
                    Picker("", selection: $settings.newAppTier) {
                        ForEach(Tier.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                GridRow {
                    Text("Hide again after")
                    Picker("", selection: $settings.rehideDelay) {
                        ForEach(AppSettings.rehideChoices, id: \.self) { Text(Self.delayLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
            Toggle("Open at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LoginItem.setEnabled(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                    }
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
            .toggleStyle(.checkbox)
            .disabled(!LoginItem.isAvailable)
            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 13))
    }

    static func delayLabel(_ seconds: Double) -> String {
        switch seconds {
        case 0: "Never"
        case ..<60: "\(Int(seconds)) seconds"
        default: "\(Int(seconds / 60)) minute\(seconds == 60 ? "" : "s")"
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        section("Updates") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(updates.versionText)
                    Text(updates.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(updates.status.isFailure ? Color.red : Color.secondary)
                        .lineLimit(3)
                }
                Spacer()
                if case .available = updates.status {
                    Button("Update", action: updates.install)
                } else {
                    Button("Check for updates", action: updates.check)
                        .disabled(!updates.canCheck)
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// One app: its icon, its name, and the three tiers to pick from.
private struct AppRow: View {
    let app: KnownApp
    let isPresent: Bool
    @Binding var tier: Tier
    let forget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = MenuBarInventory.icon(forBundleID: app.bundleID) {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.2))
                }
            }
            .frame(width: 24, height: 24)
            .opacity(isPresent ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                if !isPresent {
                    Text("No icon in the menu bar right now")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Picker("", selection: $tier) {
                ForEach(Tier.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
        .contextMenu {
            if !isPresent {
                Button("Forget \(app.name)", action: forget)
            }
        }
    }
}
