import XCTest
@testable import Fretwork

final class BoardGeometryTests: XCTestCase {
    private static let size = CGSize(width: 1000, height: 300)

    private func geometry(frets: Int = 22, strings: Int = 6, flipped: Bool = false,
                          margins: BoardGeometry.Margins = .labelled) -> BoardGeometry {
        BoardGeometry(size: Self.size, frets: frets, strings: strings, flipped: flipped, margins: margins)
    }

    /// The detection board's layout must not have moved when this geometry was
    /// generalised out of it. These are the numbers the old private struct
    /// produced: `CGRect(x: 62, y: 34, width: size.width - 62, height: size.height - 38)`.
    func testLabelledMarginsReproduceTheDetectionBoardsLayout() {
        let geometry = geometry()
        XCTAssertEqual(geometry.board, CGRect(x: 62, y: 34, width: 938, height: 262))
        XCTAssertEqual(geometry.columns, 23)
        XCTAssertEqual(geometry.x(fret: 0), 62 + 938 * 0.5 / 23, accuracy: 0.001)
        XCTAssertEqual(geometry.y(string: 0), 34 + 262 * 5.5 / 6, accuracy: 0.001)
        XCTAssertEqual(geometry.leadingEdge(fret: 0), 62, accuracy: 0.001)
        XCTAssertEqual(geometry.columnWidth, 938.0 / 23, accuracy: 0.001)
        XCTAssertEqual(geometry.stringSpacing, 262.0 / 6, accuracy: 0.001)
    }

    func testUnflippedPutsTheLowEAtTheBottom() {
        let geometry = geometry()
        XCTAssertGreaterThan(geometry.y(string: 0), geometry.y(string: 5), "Low E should sit below the high e")
    }

    func testFlippingSwapsTheOutermostStringsAndNothingElse() {
        let normal = geometry()
        let flipped = geometry(flipped: true)
        XCTAssertEqual(flipped.y(string: 0), normal.y(string: 5), accuracy: 0.001)
        XCTAssertEqual(flipped.y(string: 5), normal.y(string: 0), accuracy: 0.001)
        XCTAssertEqual(flipped.x(fret: 7), normal.x(fret: 7), accuracy: 0.001, "flipping must not move anything horizontally")
        XCTAssertEqual(flipped.midY, normal.midY, accuracy: 0.001)
    }

    /// The modules need 12- and 15-fret boards as well as the detection
    /// board's 22, so the column count cannot be baked in.
    func testFretCountChangesTheColumnsAndTheirWidth() {
        for frets in [12, 15, 22] {
            let geometry = geometry(frets: frets)
            XCTAssertEqual(geometry.columns, frets + 1)
            XCTAssertEqual(geometry.columnWidth, 938 / CGFloat(frets + 1), accuracy: 0.001)
            XCTAssertGreaterThan(geometry.x(fret: frets), geometry.x(fret: 0))
            XCTAssertLessThan(geometry.x(fret: frets), geometry.board.maxX)
        }
    }

    func testStringCountIsNotHardcodedToSix() {
        let four = geometry(strings: 4)
        XCTAssertEqual(four.stringSpacing, 262.0 / 4, accuracy: 0.001)
        XCTAssertGreaterThan(four.y(string: 0), four.y(string: 3))
        XCTAssertEqual(four.midY, (four.y(string: 0) + four.y(string: 3)) / 2, accuracy: 0.001)
    }

    func testMarginsNoneUsesTheWholeBounds() {
        let bare = geometry(margins: .none)
        XCTAssertEqual(bare.board, CGRect(origin: .zero, size: Self.size))
    }

    // MARK: - Hit testing

    /// The strongest check available on the geometry: every position drawn
    /// must map back to itself when the point it was drawn at is hit-tested.
    /// A sign error in either direction breaks this for half the board.
    func testEveryPositionRoundTripsThroughHitTesting() {
        for flipped in [false, true] {
            let geometry = geometry(flipped: flipped)
            for string in 0..<6 {
                for fret in 0...22 {
                    let position = FretPosition(string: string, fret: fret)
                    XCTAssertEqual(
                        geometry.position(at: geometry.point(position), frets: 22),
                        position,
                        "flipped: \(flipped), string \(string) fret \(fret)"
                    )
                }
            }
        }
    }

    func testAPointOutsideTheGridIsNotAPosition() {
        let geometry = geometry()
        // The string-name gutter, left of the board.
        XCTAssertNil(geometry.position(at: CGPoint(x: 30, y: 150), frets: 22))
        // The fret-number row, above it.
        XCTAssertNil(geometry.position(at: CGPoint(x: 500, y: 13), frets: 22))
        XCTAssertNil(geometry.position(at: CGPoint(x: -5, y: 150), frets: 22))
        XCTAssertNotNil(geometry.position(at: CGPoint(x: 500, y: 150), frets: 22))
    }

    func testADegenerateSizeDoesNotProduceANegativeBoard() {
        let tiny = BoardGeometry(size: CGSize(width: 10, height: 10), frets: 22, flipped: false)
        XCTAssertGreaterThanOrEqual(tiny.board.width, 0)
        XCTAssertGreaterThanOrEqual(tiny.board.height, 0)
    }
}
