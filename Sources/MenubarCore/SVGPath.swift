import Foundation

/// One step of an SVG path, in absolute coordinates.
public enum SVGPathCommand: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case curve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

/// Reads the `d` attribute of an SVG path. Covers the commands the icon set
/// uses (M L H V C Z, absolute or relative). Anything else returns nil rather
/// than drawing a shape that is subtly wrong.
public enum SVGPath {
    public static func parse(_ d: String) -> [SVGPathCommand]? {
        let characters = Array(d)
        var index = 0
        var commands: [SVGPathCommand] = []
        var current = (x: 0.0, y: 0.0)
        var subpathStart = current
        var letter: Character?

        func skipSeparators() {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
                index += 1
            }
        }

        // SVG packs numbers tightly: ".5.5" and "1-2" are two numbers each.
        func number() -> Double? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            var seenDigit = false
            var seenPoint = false
            while index < characters.count {
                let character = characters[index]
                if character.isASCII, character.isNumber {
                    seenDigit = true
                } else if character == ".", !seenPoint {
                    seenPoint = true
                } else {
                    break
                }
                index += 1
            }
            guard seenDigit, let value = Double(String(characters[start..<index])) else {
                index = start
                return nil
            }
            return value
        }

        while true {
            skipSeparators()
            guard index < characters.count else { break }
            if characters[index].isLetter {
                letter = characters[index]
                index += 1
                if letter == "Z" || letter == "z" {
                    commands.append(.close)
                    current = subpathStart
                    continue
                }
            }
            guard let command = letter else { return nil }
            // Lowercase commands are relative to the current point.
            let origin = command.isLowercase ? current : (x: 0.0, y: 0.0)

            switch command.uppercased() {
            case "M":
                guard let x = number(), let y = number() else { return nil }
                current = (origin.x + x, origin.y + y)
                subpathStart = current
                commands.append(.move(x: current.x, y: current.y))
                // Coordinate pairs that follow a move without a letter are lines.
                letter = command.isLowercase ? "l" : "L"
            case "L":
                guard let x = number(), let y = number() else { return nil }
                current = (origin.x + x, origin.y + y)
                commands.append(.line(x: current.x, y: current.y))
            case "H":
                guard let x = number() else { return nil }
                current.x = origin.x + x
                commands.append(.line(x: current.x, y: current.y))
            case "V":
                guard let y = number() else { return nil }
                current.y = origin.y + y
                commands.append(.line(x: current.x, y: current.y))
            case "C":
                guard let c1x = number(), let c1y = number(), let c2x = number(), let c2y = number(),
                      let x = number(), let y = number() else { return nil }
                commands.append(.curve(
                    c1x: origin.x + c1x, c1y: origin.y + c1y,
                    c2x: origin.x + c2x, c2y: origin.y + c2y,
                    x: origin.x + x, y: origin.y + y
                ))
                current = (origin.x + x, origin.y + y)
            default:
                return nil
            }
        }
        return commands.isEmpty ? nil : commands
    }
}
