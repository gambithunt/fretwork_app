import XCTest
@testable import Fretwork

@MainActor
final class FretPositionResolverTests: XCTestCase {
    // E4 is the most ambiguous note on the neck: open high E, or the same
    // pitch at the 5th, 9th, 14th and 19th frets of the strings below it.
    private let e4 = 64

    func testColdStartPrefersTheOpenString() {
        let resolver = FretPositionResolver()
        XCTAssertEqual(resolver.resolve(midiNote: e4).first?.position, FretPosition(string: 5, fret: 0))
    }

    func testColdStartWithoutAnOpenOptionPrefersTheLowestFret() {
        let resolver = FretPositionResolver()
        // D♯4 can't be played open in standard tuning.
        XCTAssertEqual(resolver.resolve(midiNote: 63).first?.position, FretPosition(string: 4, fret: 4))
    }

    func testTheChoiceFollowsTheHandUpTheNeck() {
        let resolver = FretPositionResolver()
        // D5 is only reachable high up, which puts the hand around fret 10.
        XCTAssertEqual(resolver.resolve(midiNote: 74).first?.position, FretPosition(string: 5, fret: 10))
        // The same E4 that a cold resolver calls an open string is now read as
        // the 9th fret, because that's where the hand already is.
        XCTAssertEqual(resolver.resolve(midiNote: e4).first?.position, FretPosition(string: 3, fret: 9))
    }

    func testAnOpenStringDoesNotMoveTheHandEstimate() {
        let resolver = FretPositionResolver()
        // Only one place to play G♯5: fret 20. The hand is now unambiguously high.
        XCTAssertEqual(resolver.resolve(midiNote: 84).first?.position, FretPosition(string: 5, fret: 20))
        // A2 is best explained as the open A — reaching back to fret 5 is far.
        XCTAssertEqual(resolver.resolve(midiNote: 45).first?.position, FretPosition(string: 1, fret: 0))
        // That open string said nothing about the hand, so it must still be
        // read as up at fret 20, not dragged down to the nut.
        XCTAssertEqual(resolver.resolve(midiNote: e4).first?.position, FretPosition(string: 1, fret: 19))
    }

    func testTheEstimateExpiresAfterSilence() {
        let resolver = FretPositionResolver()
        let start = ContinuousClock.now
        XCTAssertEqual(resolver.resolve(midiNote: 84, now: start).first?.position, FretPosition(string: 5, fret: 20))
        // Long enough that the hand could have gone anywhere, so the resolver
        // falls back to its cold-start reading rather than trusting stale
        // information.
        let later = start.advanced(by: .seconds(5))
        XCTAssertEqual(resolver.resolve(midiNote: e4, now: later).first?.position, FretPosition(string: 5, fret: 0))
    }

    func testEveryCandidateIsReturnedRankedWithOnePrimary() {
        let resolver = FretPositionResolver()
        let ranked = resolver.resolve(midiNote: e4)
        XCTAssertEqual(ranked.count, 5)
        XCTAssertEqual(ranked.map(\.rank), [0, 1, 2, 3, 4])
        XCTAssertEqual(ranked.filter(\.isPrimary).count, 1)
        XCTAssertEqual(Set(ranked.map(\.position)), Set(GuitarTuning.positions(forMIDI: e4)))
    }

    func testResetReturnsToColdStartBehaviour() {
        let resolver = FretPositionResolver()
        _ = resolver.resolve(midiNote: 74)
        resolver.reset()
        XCTAssertEqual(resolver.resolve(midiNote: e4).first?.position, FretPosition(string: 5, fret: 0))
    }
}
