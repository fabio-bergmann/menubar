import Foundation

/// Where an app's menu bar icons live.
public enum Tier: String, Codable, CaseIterable, Sendable {
    /// Always in the menu bar.
    case visible
    /// Hidden until the menu bar is clicked, then hidden again.
    case onClick
    /// Never in the menu bar.
    case never

    public var label: String {
        switch self {
        case .visible: "Always"
        case .onClick: "On click"
        case .never: "Never"
        }
    }

    /// Whether the icons are hidden, with the On click icons showing or not.
    public func isHidden(revealed: Bool) -> Bool {
        switch self {
        case .visible: false
        case .onClick: !revealed
        case .never: true
        }
    }
}
