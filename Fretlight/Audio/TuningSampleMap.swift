import Foundation

/// Resolves a position in any tuning to a recorded take plus the pitch shift
/// needed to sound it.
///
/// The library is recorded in standard tuning at every fret, so standard needs
/// no resampling at all — every position is a direct lookup, and
/// `testStandardTuningIsNeverResampled` pins that. The other fourteen tunings
/// have positions no take covers, and those shift from the **same string's**
/// nearest recorded position rather than from whichever string happens to hold
/// the right pitch. Borrowing the correct pitch off a different string would
/// give the right note with the wrong instrument: string gauge, winding and
/// pickup position are most of what makes a low E sound like a low E rather
/// than like the A string played high.
///
/// "Nearest recorded position on the same string" is a clamp. A string tuned
/// down by *n* semitones can play everything above its *n*th fret from a real
/// take; only the frets below that have nowhere to come from, and they shift
/// from fret 0. Tuned up, only the very top of the neck runs out.
enum TuningSampleMap {
    struct Resolution: Sendable, Equatable {
        /// The fret whose recorded take is used.
        let fret: Int
        /// Frequency ratio to apply to that take. Exactly 1 when the position
        /// is recorded as-is.
        let rateMultiplier: Double
        /// How far the take is being shifted, in semitones. 0 means untouched;
        /// the sign says which way. Kept alongside the ratio because it is the
        /// number a person can judge — see the limits recorded below.
        let semitoneShift: Int

        var isResampled: Bool { semitoneShift != 0 }
    }

    /// Every table, built once on first use. A note trigger must not re-derive
    /// this, and there are only fifteen of them.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [TuningID: [Resolution?]] = [:]

        func table(for tuning: Tuning) -> [Resolution?] {
            lock.lock()
            defer { lock.unlock() }
            if let existing = tables[tuning.id] { return existing }
            let built = TuningSampleMap.buildTable(for: tuning)
            tables[tuning.id] = built
            return built
        }
    }

    private static func slot(string: Int, fret: Int) -> Int {
        string * (NoteSampleLibrary.highestFret + 1) + fret
    }

    private static func buildTable(for tuning: Tuning) -> [Resolution?] {
        let strings = NoteSampleLibrary.stringCount
        let topFret = NoteSampleLibrary.highestFret
        var table = [Resolution?](repeating: nil, count: strings * (topFret + 1))

        for string in 0..<strings {
            guard Tunings.standard.openMIDINotes.indices.contains(string),
                  tuning.openMIDINotes.indices.contains(string) else { continue }
            let recordedOpen = Tunings.standard.openMIDINotes[string]
            let actualOpen = tuning.openMIDINotes[string]

            for fret in 0...topFret {
                let wanted = actualOpen + fret
                // The fret on this string whose recording is closest in pitch.
                let ideal = wanted - recordedOpen
                let source = min(max(ideal, 0), topFret)
                let shift = wanted - (recordedOpen + source)
                table[slot(string: string, fret: fret)] = Resolution(
                    fret: source,
                    rateMultiplier: pow(2, Double(shift) / 12),
                    semitoneShift: shift
                )
            }
        }
        return table
    }

    /// - Returns: nil for a position off the neck.
    static func resolve(tuning: Tuning, string: Int, fret: Int) -> Resolution? {
        guard (0..<NoteSampleLibrary.stringCount).contains(string),
              (0...NoteSampleLibrary.highestFret).contains(fret)
        else { return nil }
        return cache.table(for: tuning)[slot(string: string, fret: fret)]
    }

    /// The largest shift any position in `tuning` needs, in semitones. The
    /// number to look at when asking how far a tuning stretches the library.
    static func largestShift(in tuning: Tuning) -> Int {
        var largest = 0
        for string in 0..<NoteSampleLibrary.stringCount {
            for fret in 0...NoteSampleLibrary.highestFret {
                guard let resolution = resolve(tuning: tuning, string: string, fret: fret) else { continue }
                largest = max(largest, abs(resolution.semitoneShift))
            }
        }
        return largest
    }
}
