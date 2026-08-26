import XCTest
@testable import Fretwork

/// The library is recorded in standard tuning at every fret, so standard must
/// never resample and the other fourteen tunings must sound the right pitch
/// from the right string.
///
/// These assert on *sounded pitch*, not on fret numbers, for the reason
/// `CLAUDE.md` gives about porting fret arrays: a wrong table is still six
/// plausible fret numbers, and it compiles and renders exactly like a right one.
final class TuningSampleMapTests: XCTestCase {
    private func midi(of resolution: TuningSampleMap.Resolution, string: Int) -> Double {
        // What the chosen take sounds, plus the shift applied to it.
        let recorded = Tunings.standard.openMIDINotes[string] + resolution.fret
        return Double(recorded) + 12 * log2(resolution.rateMultiplier)
    }

    /// The whole reason for recording every fret.
    func testStandardTuningIsNeverResampled() {
        for string in 0..<NoteSampleLibrary.stringCount {
            for fret in 0...NoteSampleLibrary.highestFret {
                let resolution = TuningSampleMap.resolve(tuning: Tunings.standard, string: string, fret: fret)
                XCTAssertEqual(resolution?.fret, fret, "string \(string) fret \(fret) must use its own take")
                XCTAssertEqual(resolution?.rateMultiplier, 1)
                XCTAssertEqual(resolution?.semitoneShift, 0)
                XCTAssertEqual(resolution?.isResampled, false)
            }
        }
        XCTAssertEqual(TuningSampleMap.largestShift(in: Tunings.standard), 0)
    }

    /// Every position in every tuning must sound the pitch that tuning implies.
    func testEveryTuningSoundsTheCorrectPitchAtEveryPosition() {
        for tuning in Tunings.all {
            for string in 0..<NoteSampleLibrary.stringCount {
                for fret in 0...NoteSampleLibrary.highestFret {
                    let resolution = try? XCTUnwrap(TuningSampleMap.resolve(tuning: tuning, string: string, fret: fret))
                    guard let resolution else { return XCTFail("\(tuning.name) string \(string) fret \(fret) unresolved") }
                    let expected = Double(tuning.openMIDINotes[string] + fret)
                    XCTAssertEqual(
                        midi(of: resolution, string: string),
                        expected,
                        accuracy: 0.0001,
                        "\(tuning.name) string \(string) fret \(fret)"
                    )
                }
            }
        }
    }

    /// A shifted note must come from the string it is played on, never from
    /// whichever string happens to hold the right pitch — that would be the
    /// right note with the wrong instrument.
    func testAShiftedNoteComesFromItsOwnString() {
        for tuning in Tunings.all {
            for string in 0..<NoteSampleLibrary.stringCount {
                for fret in 0...NoteSampleLibrary.highestFret {
                    guard let resolution = TuningSampleMap.resolve(tuning: tuning, string: string, fret: fret) else { continue }
                    XCTAssertTrue(
                        (0...NoteSampleLibrary.highestFret).contains(resolution.fret),
                        "\(tuning.name) string \(string) fret \(fret) resolved off the neck"
                    )
                }
            }
        }
    }

    /// Only the frets a detuned string cannot reach need shifting. A string
    /// down *n* semitones plays everything from its *n*th fret up from a real
    /// take, which is most of the neck.
    func testOnlyThePositionsBelowTheDetuneNeedShifting() {
        // Drop D lowers string 0 by two semitones and leaves the rest alone.
        let dropD = Tunings.dropD
        for fret in 0...NoteSampleLibrary.highestFret {
            let resolution = TuningSampleMap.resolve(tuning: dropD, string: 0, fret: fret)
            if fret < 2 {
                XCTAssertTrue(resolution?.isResampled ?? false, "fret \(fret) has no take to use")
            } else {
                XCTAssertEqual(resolution?.semitoneShift, 0, "fret \(fret) has a real take and must use it")
                XCTAssertEqual(resolution?.fret, fret - 2)
            }
        }
        for string in 1..<NoteSampleLibrary.stringCount {
            for fret in 0...NoteSampleLibrary.highestFret {
                XCTAssertEqual(TuningSampleMap.resolve(tuning: dropD, string: string, fret: fret)?.semitoneShift, 0,
                               "Drop D leaves string \(string) at standard pitch")
            }
        }
    }

    /// The audible limit this workstream asks to record. Drop A is the worst
    /// case in the set: its low string sits seven semitones below the recorded
    /// one, so its open position is a low E take pitched down a fifth.
    func testDropAIsTheWorstCaseAndIsSevenSemitones() {
        XCTAssertEqual(TuningSampleMap.largestShift(in: Tunings.dropA), 7)

        let worst = Tunings.all.map { ($0.name, TuningSampleMap.largestShift(in: $0)) }
        let largest = worst.map(\.1).max()
        XCTAssertEqual(largest, 7, "if a tuning ever needs more than Drop A, the note about audible limits needs revisiting")

        // And that shift really is downward — pitching a take up thins it, but
        // pitching it down is what stretches its character.
        let open = TuningSampleMap.resolve(tuning: Tunings.dropA, string: 0, fret: 0)
        XCTAssertEqual(open?.semitoneShift, -7)
        XCTAssertEqual(open?.fret, 0, "it must stretch the open low E, the lowest take that string has")
        XCTAssertEqual(open?.rateMultiplier ?? 0, 0.6674, accuracy: 0.0001)
    }

    /// Above the shifted region a detuned string is exact, so most of even the
    /// worst tuning is untouched audio.
    func testMostOfEvenTheWorstTuningUsesRealTakes() {
        var exact = 0
        var total = 0
        for string in 0..<NoteSampleLibrary.stringCount {
            for fret in 0...NoteSampleLibrary.highestFret {
                guard let resolution = TuningSampleMap.resolve(tuning: Tunings.dropA, string: string, fret: fret) else { continue }
                total += 1
                if !resolution.isResampled { exact += 1 }
            }
        }
        XCTAssertEqual(total, 138)
        XCTAssertGreaterThan(Double(exact) / Double(total), 0.7, "\(exact) of \(total) positions are real takes")
    }

    func testAPositionOffTheNeckResolvesToNothing() {
        XCTAssertNil(TuningSampleMap.resolve(tuning: Tunings.standard, string: 6, fret: 0))
        XCTAssertNil(TuningSampleMap.resolve(tuning: Tunings.standard, string: 0, fret: 23))
        XCTAssertNil(TuningSampleMap.resolve(tuning: Tunings.standard, string: -1, fret: 0))
    }

    /// The table is cached; a second lookup must be the same answer, not a
    /// freshly derived one that happens to agree.
    func testRepeatedLookupsAreStable() {
        let first = TuningSampleMap.resolve(tuning: Tunings.openC, string: 3, fret: 11)
        let second = TuningSampleMap.resolve(tuning: Tunings.openC, string: 3, fret: 11)
        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }
}
