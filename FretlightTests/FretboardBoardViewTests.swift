import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

@MainActor
final class FretboardBoardViewTests: XCTestCase {

    func testDotPitchClassUsesItsPositionRatherThanItsLessonLabel() {
        let degreeLabelledDot = FretboardDot(
            id: "degree",
            position: FretPosition(string: 0, fret: 3),
            label: "♭3",
            color: .orange
        )

        XCTAssertEqual(degreeLabelledDot.pitchClass(in: .standard), PitchClass(7), "low E at fret 3 is G, whatever lesson label the dot displays")
        XCTAssertEqual(degreeLabelledDot.pitchClass(in: .dropD), PitchClass(5), "the same visual cell follows the board's active tuning")
    }
    private func dot(_ id: String, string: Int, fret: Int) -> FretboardDot {
        FretboardDot(id: id, position: FretPosition(string: string, fret: fret), label: "A", color: .green)
    }

    private func render(_ view: some View, size: CGSize = CGSize(width: 900, height: 280)) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layout()
        // Forcing a draw is what actually exercises the Canvas closure; simply
        // constructing the view would not.
        XCTAssertNotNil(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    }

    // MARK: - Identity, which is what drives the animation

    /// The board animates dots between layouts by matching `id`. That only
    /// works if a dot that has moved compares unequal to its previous self —
    /// otherwise SwiftUI sees no change and the dot teleports.
    func testADotThatMovesComparesUnequalToItsPreviousSelf() {
        let before = dot("root", string: 0, fret: 3)
        let after = dot("root", string: 0, fret: 5)
        XCTAssertEqual(before.id, after.id, "the id is what ties the two together")
        XCTAssertNotEqual(before, after, "a moved dot must register as a change")
    }

    func testDotsAreMatchedByIdNotByPosition() {
        let a = dot("first", string: 2, fret: 7)
        let b = dot("second", string: 2, fret: 7)
        XCTAssertNotEqual(a.id, b.id, "two dots at one position must stay distinguishable")
        XCTAssertNotEqual(a, b)
    }

    func testAnUnchangedLayoutComparesEqualSoNoAnimationFires() {
        let dots = [dot("a", string: 0, fret: 0), dot("b", string: 3, fret: 5)]
        XCTAssertEqual(dots, [dot("a", string: 0, fret: 0), dot("b", string: 3, fret: 5)])
    }

    // MARK: - Rendering

    func testTheBoardRendersAcrossTheFretCountsTheModulesUse() {
        for frets in [12, 15, 22] {
            render(FretboardBoardView(dots: [dot("a", string: 0, fret: 0)], frets: frets))
        }
    }

    func testTheBoardRendersEmptyAndFullyPopulated() {
        render(FretboardBoardView(dots: []))

        let everyPosition = (0..<6).flatMap { string in
            (0...22).map { fret in dot("\(string):\(fret)", string: string, fret: fret) }
        }
        render(FretboardBoardView(dots: everyPosition))
    }

    func testTheBoardRendersFlippedAndUnderANonStandardTuning() {
        render(FretboardBoardView(dots: [dot("a", string: 0, fret: 3)], flipped: true))
        render(FretboardBoardView(dots: [dot("a", string: 0, fret: 3)], tuning: Tunings.dadgad))
    }

    /// A compact diagram has no room for the fret numbers and string names, so
    /// it drops both and reclaims the margins they occupied.
    func testTheBoardRendersUnlabelledWithNoMargins() {
        render(
            FretboardBoardView(dots: [dot("a", string: 0, fret: 2)], frets: 4, margins: .none, showsLabels: false),
            size: CGSize(width: 200, height: 120)
        )
    }

    func testEveryDotDecorationRenders() {
        var decorated = dot("decorated", string: 2, fret: 5)
        decorated.radius = 9
        decorated.alpha = 0.45
        decorated.ring = .white
        decorated.ringAlpha = 0.8
        decorated.outline = true
        decorated.labelColor = .black
        decorated.role = "root"
        render(FretboardBoardView(dots: [decorated]))
    }

    func testAPulsingDotRenders() {
        let dots = [dot("a", string: 1, fret: 4)]
        for pulse in [0.0, 0.5, 1.0] {
            render(FretboardBoardView(dots: dots, pulses: ["a": pulse]))
        }
    }

    func testOverlaysRenderInBothKinds() {
        let dots = (0..<5).map { dot("d\($0)", string: $0, fret: $0 + 2) }
        let group = FretboardOverlay(id: "box", kind: .group, color: .yellow, dotIDs: dots.map(\.id))
        let sequence = FretboardOverlay(id: "run", kind: .sequence, color: .cyan, dotIDs: dots.map(\.id).reversed())
        render(FretboardBoardView(dots: dots, overlays: [group, sequence]))
    }

    /// An overlay naming dots that are not on the board must not stop the
    /// board drawing.
    func testAnOverlayOverNoPresentDotsStillRenders() {
        let stray = FretboardOverlay(id: "ghost", kind: .sequence, color: .red, dotIDs: ["nope", "also-nope"])
        render(FretboardBoardView(dots: [dot("a", string: 0, fret: 0)], overlays: [stray]))
    }

    func testAnInteractiveBoardRenders() {
        render(FretboardBoardView(dots: [dot("a", string: 0, fret: 0)], onHit: { _ in }, onLongPress: { _ in }))
    }

    func testADegenerateSizeDoesNotCrashTheBoard() {
        render(FretboardBoardView(dots: [dot("a", string: 0, fret: 0)]), size: CGSize(width: 10, height: 10))
    }
}
