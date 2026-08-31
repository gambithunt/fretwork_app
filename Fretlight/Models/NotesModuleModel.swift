import Foundation
import SwiftUI

/// The Notes module's logic, separated from its view so it can be tested
/// without rendering anything.
///
/// Ported from `../fretwork/src/lib/modules/Notes.svelte`. The board is both
/// output and input, and the module's whole idea is that the two ways of
/// editing it produce the same dots:
///
/// - tap a note button → toggle **every** position of that note
/// - tap an empty cell → drop a note where the finger landed
/// - tap an existing dot → hear it again
/// - long-press a dot → remove just that one
///
/// State is one set of placed positions keyed `"string:fret"`, so
/// button-lit dots and tapped dots are the same dots, deduplicated by position.
/// That single set is why a note button can be "on" only when every one of its
/// positions is present — which is the rule the web states and this keeps.
@MainActor
@Observable
final class NotesModuleModel {
    /// `"string:fret"`, the web app's key format, kept identical so a saved
    /// board means the same thing in both apps.
    private(set) var placed: [String] = []

    /// Per-dot emphasis driven by playback, so what is heard and what lights up
    /// cannot drift apart — the required outcome workstream 006 states.
    private(set) var pulses: [String: Double] = [:]

    var tuning: Tuning
    /// Mutable, unlike every other module's `highestFret`: Notes is the one
    /// module where a tap on empty board places a note anywhere it lands, so
    /// when the screen's "show the full neck" toggle widens the *drawn*
    /// board it has to widen this too — otherwise a tap past fret 12 would
    /// resolve to a real cell that silently refuses to place anything.
    var highestFret = LearningModule.notes.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var sequencer: NoteSequencer?

    /// - Parameter play: sounds one position. Injected so the module can be
    ///   tested without an audio graph.
    init(
        tuning: Tuning = Tunings.standard,
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.tuning = tuning
        self.store = store
        self.play = play
        placed = store?.state.modules.notes.placed ?? PracticeState.Modules.Notes.defaultPlaced
    }

    // MARK: - Derived board

    static func key(string: Int, fret: Int) -> String { "\(string):\(fret)" }

    func position(forKey key: String) -> FretPosition? {
        let parts = key.split(separator: ":")
        guard parts.count == 2,
              let string = Int(parts[0]),
              let fret = Int(parts[1]),
              tuning.openMIDINotes.indices.contains(string),
              (0...highestFret).contains(fret)
        else { return nil }
        return FretPosition(string: string, fret: fret)
    }

    func midi(at position: FretPosition) -> Int {
        tuning.openMIDINotes[position.string] + position.fret
    }

    func pitchClass(at position: FretPosition) -> PitchClass {
        PitchClass(midi(at: position))
    }

    /// Dot ids are `"p" + key` and depend only on position, never on content —
    /// `FretboardDot`'s docstring records why: an id derived from content turns
    /// every slide into a cross-fade.
    var dots: [FretboardDot] {
        placed.compactMap { key in
            guard let position = position(forKey: key) else { return nil }
            let pitchClass = pitchClass(at: position)
            return FretboardDot(
                id: "p" + key,
                position: position,
                label: pitchClass.name(),
                color: NotePalette.color(for: pitchClass)
            )
        }
    }

    /// The distinct notes on the neck, low to high, with how many of each.
    var present: [(pitchClass: PitchClass, count: Int)] {
        var counts: [Int: Int] = [:]
        for key in placed {
            guard let position = position(forKey: key) else { continue }
            counts[pitchClass(at: position).value, default: 0] += 1
        }
        return counts.keys.sorted().map { (PitchClass($0), counts[$0] ?? 0) }
    }

    /// `C♯ = D♭` and friends, for the notes actually on the board.
    var enharmonicHints: [String] {
        present.compactMap { note in
            guard let alias = note.pitchClass.enharmonicAlias else { return nil }
            return "\(note.pitchClass.name()) = \(alias)"
        }
    }

    var discovery: ChordDiscoveryResult {
        ChordDiscovery.discover(placed.compactMap { key -> DiscoveredNote? in
            guard let position = position(forKey: key) else { return nil }
            return DiscoveredNote(
                pitchClass: pitchClass(at: position),
                midiNote: midi(at: position),
                string: position.string
            )
        })
    }

    var chordLabel: String {
        if let symbol = discovery.primary?.symbol { return symbol }
        switch discovery.status {
        case .unknown: return "No common match"
        case .empty: return "—"
        default: return "Keep adding notes"
        }
    }

    // MARK: - Editing

    private func allKeys(of pitchClass: PitchClass) -> [String] {
        Positions.findAll(pitchClasses: [pitchClass], tuning: tuning, fretCount: highestFret)
            .map { Self.key(string: $0.string, fret: $0.fret) }
    }

    /// A note button is lit only when **every** one of its positions is on the
    /// board — so the button reflects the board rather than a separate
    /// selection that could disagree with it.
    func isNoteActive(_ pitchClass: PitchClass) -> Bool {
        let keys = allKeys(of: pitchClass)
        guard !keys.isEmpty else { return false }
        let current = Set(placed)
        return keys.allSatisfy(current.contains)
    }

    func toggleNote(_ pitchClass: PitchClass) {
        let keys = allKeys(of: pitchClass)
        let current = Set(placed)
        if keys.allSatisfy(current.contains) {
            let dropping = Set(keys)
            commit(placed.filter { !dropping.contains($0) })
        } else {
            commit(placed + keys.filter { !current.contains($0) })
        }
    }

    /// Tap an empty cell to place a note and hear it; tap an existing dot to
    /// replay it. Either way the note at that position sounds and pulses.
    func tapCell(string: Int, fret: Int) {
        let key = Self.key(string: string, fret: fret)
        guard let position = position(forKey: key) else { return }
        if !placed.contains(key) { commit(placed + [key]) }
        play(position)
        pulse("p" + key)
    }

    func longPressCell(string: Int, fret: Int) {
        let key = Self.key(string: string, fret: fret)
        commit(placed.filter { $0 != key })
    }

    func clearAll() {
        stop()
        commit([])
    }

    private func commit(_ next: [String]) {
        placed = next
        store?.update { $0.modules.notes.placed = next }
    }

    // MARK: - Playback

    /// Plays everything on the board, lowest pitch first, pulsing each dot as
    /// it sounds. The gap is the web's 0.26s — quick enough to hear the notes
    /// as one thing rather than a list.
    func playAll() {
        let ordered = dots.sorted { midi(at: $0.position) < midi(at: $1.position) }
        guard !ordered.isEmpty else { return }

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, rate, gain in
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = rate
                _ = gain
                self.play(position)
            }
        }
        self.sequencer = sequencer

        var options = NoteSequencer.Options()
        options.gap = 0.26
        options.onHit = { [weak self] _, index in
            Task { @MainActor [weak self] in
                guard let self, ordered.indices.contains(index) else { return }
                self.pulse(ordered[index].id)
            }
        }
        sequencer.play(ordered.map(\.position), options: options)
    }

    /// Cancellation has to be total — no further audio and no further pulses —
    /// and it has to happen on navigation away as well as on an explicit stop.
    func stop() {
        sequencer?.stop()
        pulses.removeAll()
    }

    private func pulse(_ id: String) {
        pulses[id] = 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            self?.pulses[id] = nil
        }
    }
}
