import SwiftUI
import XCTest
@testable import Fretwork

final class FretboardHitTestTests: XCTestCase {
    private static let size = CGSize(width: 900, height: 280)
    private static let frets = 22

    private func geometry(flipped: Bool = false) -> BoardGeometry {
        BoardGeometry(size: Self.size, frets: Self.frets, flipped: flipped)
    }

    private func dot(_ id: String, string: Int, fret: Int) -> FretboardDot {
        FretboardDot(id: id, position: FretPosition(string: string, fret: fret), label: "x", color: .green)
    }

    private func hit(_ point: CGPoint, dots: [FretboardDot], flipped: Bool = false) -> FretboardHit? {
        FretboardHitTest.resolve(location: point, geometry: geometry(flipped: flipped), frets: Self.frets, dots: dots)
    }

    func testTappingADotReportsThatDot() {
        let target = dot("a", string: 2, fret: 5)
        let point = geometry().point(target.position)
        XCTAssertEqual(hit(point, dots: [target]), .dot(target))
    }

    /// The gesture the Notes screen depends on: an empty cell must be
    /// reportable, including one sitting right beside an occupied cell.
    func testTappingAnEmptyCellReportsTheCell() {
        let occupied = dot("a", string: 2, fret: 5)
        let empty = FretPosition(string: 2, fret: 6)
        XCTAssertEqual(hit(geometry().point(empty), dots: [occupied]), .cell(empty))
    }

    func testAnEmptyBoardReportsCellsEverywhere() {
        for string in 0..<6 {
            for fret in 0...Self.frets {
                let position = FretPosition(string: string, fret: fret)
                XCTAssertEqual(hit(geometry().point(position), dots: []), .cell(position))
            }
        }
    }

    func testTappingOutsideTheGridReportsNothing() {
        // The string-name gutter and the fret-number row are not the board.
        XCTAssertNil(hit(CGPoint(x: 20, y: 140), dots: []))
        XCTAssertNil(hit(CGPoint(x: 500, y: 10), dots: []))
    }

    /// The layered module views draw a focused box over recessed neighbours,
    /// so two dots can share a position. The one on top is the one a tap means.
    func testWhenDotsOverlapTheTopmostWins() {
        let beneath = dot("recessed", string: 3, fret: 7)
        let above = dot("focused", string: 3, fret: 7)
        XCTAssertEqual(hit(geometry().point(above.position), dots: [beneath, above]), .dot(above))
    }

    func testHitTestingFollowsTheFlip() {
        let target = dot("a", string: 0, fret: 4)
        let flippedPoint = geometry(flipped: true).point(target.position)
        XCTAssertEqual(hit(flippedPoint, dots: [target], flipped: true), .dot(target))
        // The same point on an unflipped board is a different string entirely,
        // so it must not resolve to the same dot.
        XCTAssertNotEqual(hit(flippedPoint, dots: [target], flipped: false), .dot(target))
    }
}
