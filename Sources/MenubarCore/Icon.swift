import Foundation

/// The app's icons: Hugeicons Pro in the stroke rounded style, the set CoWork
/// uses. Each is the path data of the icon's SVG on a 24 by 24 grid, drawn as
/// 1.5-wide strokes with round caps and joins.
///
/// To add one, copy the `d` strings from
/// ~/Dev/cowork/node_modules/@hugeicons-pro/core-stroke-rounded/dist/esm/<Name>Icon.js
/// (4.3.0 here). The Pro icons are licensed, so this file is one reason the
/// repo stays private.
public enum Icon: CaseIterable, Sendable {
    case chevronLeft
    case alert

    public static let gridSize = 24.0
    public static let strokeWidth = 1.5

    /// The paths ready to draw. Empty for a path this parser can't read, which
    /// the tests rule out for every icon here.
    public var commands: [[SVGPathCommand]] {
        Self.parsed[self] ?? []
    }

    private static let parsed: [Icon: [[SVGPathCommand]]] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.paths.compactMap(SVGPath.parse)) }
    )

    var paths: [String] {
        switch self {
        case .chevronLeft: // ArrowLeft01Icon
            ["M15 6C15 6 9.00001 10.4189 9 12C8.99999 13.5812 15 18 15 18"]
        case .alert: // Alert02Icon
            [
                "M13.9248 21H10.0752C5.44476 21 3.12955 21 2.27636 19.4939C1.42317 17.9879 2.60736 15.9914 4.97574 11.9985L6.90057 8.75333C9.17559 4.91778 10.3131 3 12 3C13.6869 3 14.8244 4.91777 17.0994 8.75332L19.0243 11.9985C21.3926 15.9914 22.5768 17.9879 21.7236 19.4939C20.8704 21 18.5552 21 13.9248 21Z",
                "M12 9V13",
                "M12.125 16.75H12M12.25 16.75C12.25 16.8881 12.1381 17 12 17C11.8619 17 11.75 16.8881 11.75 16.75C11.75 16.6119 11.8619 16.5 12 16.5C12.1381 16.5 12.25 16.6119 12.25 16.75Z",
            ]
        }
    }
}
