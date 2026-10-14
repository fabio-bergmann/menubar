import XCTest
@testable import MenubarCore

final class IconTests: XCTestCase {
    func testAbsoluteCommands() {
        XCTAssertEqual(SVGPath.parse("M12 4V20M20 12H4"), [
            .move(x: 12, y: 4), .line(x: 12, y: 20),
            .move(x: 20, y: 12), .line(x: 4, y: 12),
        ])
        XCTAssertEqual(SVGPath.parse("M0 0C1 2 3 4 5 6Z"), [
            .move(x: 0, y: 0), .curve(c1x: 1, c1y: 2, c2x: 3, c2y: 4, x: 5, y: 6), .close,
        ])
    }

    func testRelativeCommands() {
        XCTAssertEqual(SVGPath.parse("m1 1l2 0h3v4c1 1 2 2 3 3z"), [
            .move(x: 1, y: 1), .line(x: 3, y: 1), .line(x: 6, y: 1), .line(x: 6, y: 5),
            .curve(c1x: 7, c1y: 6, c2x: 8, c2y: 7, x: 9, y: 8), .close,
        ])
    }

    func testRepeatedAndPackedCoordinates() {
        // Pairs after a move are lines, and a command letter can cover several.
        XCTAssertEqual(SVGPath.parse("M0 0 1 1 2 2"), [.move(x: 0, y: 0), .line(x: 1, y: 1), .line(x: 2, y: 2)])
        XCTAssertEqual(SVGPath.parse("M0,0L1,1 2,2"), [.move(x: 0, y: 0), .line(x: 1, y: 1), .line(x: 2, y: 2)])
        XCTAssertEqual(SVGPath.parse("M.5.5L-1-2"), [.move(x: 0.5, y: 0.5), .line(x: -1, y: -2)])
    }

    func testCloseReturnsToTheStartOfTheSubpath() {
        XCTAssertEqual(SVGPath.parse("M5 5h2zl1 1"), [
            .move(x: 5, y: 5), .line(x: 7, y: 5), .close, .line(x: 6, y: 6),
        ])
    }

    func testRejectsWhatItCannotDraw() {
        XCTAssertNil(SVGPath.parse(""))
        XCTAssertNil(SVGPath.parse("12 4"))
        XCTAssertNil(SVGPath.parse("M1"))
        XCTAssertNil(SVGPath.parse("M0 0A1 1 0 0 0 2 2"))
        XCTAssertNil(SVGPath.parse("M0 0Z5 5"))
    }

    func testEveryIconParsesAndStaysOnTheGrid() {
        for icon in Icon.allCases {
            XCTAssertEqual(icon.commands.count, icon.paths.count, "\(icon) has a path that doesn't parse")
            for command in icon.commands.joined() {
                let points: [Double]
                switch command {
                case .move(let x, let y), .line(let x, let y): points = [x, y]
                case .curve(let c1x, let c1y, let c2x, let c2y, let x, let y): points = [c1x, c1y, c2x, c2y, x, y]
                case .close: points = []
                }
                XCTAssertTrue(points.allSatisfy { (0...Icon.gridSize).contains($0) }, "\(icon) leaves the 24 grid")
            }
        }
    }
}
