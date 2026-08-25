import XCTest
import SwiftUI
@testable import Fretwork

final class FretboardAccessibilityTests: XCTestCase {
    private static let tuning = Tunings.standard

    func testAHandfulOfDotsAreNamedWithTheTuningsStringNamesAndOpenSpokenForFretZero() {
        let dots = [
            FretboardDot(id: "1", position: FretPosition(string: 0, fret: 0), label: "E", color: .red),
            FretboardDot(id: "2", position: FretPosition(string: 1, fret: 2), label: "B", color: .red),
        ]
        let description = FretboardAccessibility.describe(dots: dots, tuning: Self.tuning, fretCount: 22)

        let stringNames = Self.tuning.stringNames
        XCTAssertTrue(description.contains(stringNames[0]), "should name the string using Tuning.stringNames")
        XCTAssertTrue(description.contains(stringNames[1]))
        XCTAssertTrue(description.contains("open"), "fret 0 must be spoken as open")
        XCTAssertFalse(description.contains("fret 0"), "fret 0 must not be spoken as \"fret 0\"")
    }

    func testADotsRoleAppearsInTheDescription() {
        var rootDot = FretboardDot(id: "1", position: FretPosition(string: 0, fret: 0), label: "E", color: .red)
        rootDot.role = "root"
        let description = FretboardAccessibility.describe(dots: [rootDot], tuning: Self.tuning, fretCount: 22)
        XCTAssertTrue(description.contains("root"))
    }

    func testAnEmptyBoardProducesANonEmptySensibleDescription() {
        let description = FretboardAccessibility.describe(dots: [], tuning: Self.tuning, fretCount: 22)
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.lowercased().contains("no notes"))
    }

    /// Well past the enumeration threshold, so a passing test actually proves
    /// the summary path, not just that a handful of dots happens to fit.
    func testALargeBoardSummarisesRatherThanEnumeratingEveryDot() {
        var dots: [FretboardDot] = []
        for string in 0..<6 {
            for fret in 0...22 {
                dots.append(FretboardDot(id: "\(string)-\(fret)", position: FretPosition(string: string, fret: fret), label: "x", color: .red))
            }
        }
        let description = FretboardAccessibility.describe(dots: dots, tuning: Self.tuning, fretCount: 22)

        XCTAssertTrue(description.contains("\(dots.count)"), "should state the total count rather than staying silent about size")
        XCTAssertLessThan(description.count, 400, "a summary must stay far shorter than one clause per dot")
        XCTAssertFalse(description.contains(";"), "the enumerated, semicolon-joined clause form must not be used for a large board")
    }
}
