import Foundation
import SwiftUI

/// The circle of fifths — how all the keys relate.
///
/// Ported from `../fretwork/src/lib/modules/CircleOfFifths.svelte`, the one
/// module with no fretboard as its stage.
///
/// The circle is not an arbitrary arrangement: each step clockwise is a fifth
/// up, which is why **neighbouring keys share all but one note**. That single
/// fact is what makes the ring worth drawing — the keys next to yours are the
/// ones you can move to without anything clashing, and the ones opposite are
/// the furthest away.
@MainActor
@Observable
final class CircleModuleModel {
    private(set) var selected = PitchClass(0)
    private(set) var pulses: [String: Double] = [:]

    var tuning: Tuning

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var sequencer: NoteSequencer?

    init(
        tuning: Tuning = Tunings.standard,
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.tuning = tuning
        self.store = store
        self.play = play
        selected = PitchClass(store?.state.modules.circle.selectedPitchClass ?? 0)
    }

    /// The twelve keys in fifths order, starting at C at the top.
    var keys: [PitchClass] { Harmony.circleOfFifths }

    var selectedIndex: Int { keys.firstIndex(of: selected) ?? 0 }

    /// A fifth up — clockwise. The chord that pulls hardest back to the tonic.
    var dominant: PitchClass { keys[(selectedIndex + 1) % 12] }
    /// A fifth down — anticlockwise.
    var subdominant: PitchClass { keys[(selectedIndex + 11) % 12] }
    /// Three semitones down: the same notes, a different home.
    var relativeMinor: PitchClass { selected.transposed(by: 9) }

    /// What role a key on the ring plays relative to the selected one. Only
    /// four positions have a role; the rest are context.
    enum Role: Equatable {
        case tonic, dominant, subdominant, none
    }

    func role(at index: Int) -> Role {
        if index == selectedIndex { return .tonic }
        if index == (selectedIndex + 1) % 12 { return .dominant }
        if index == (selectedIndex + 11) % 12 { return .subdominant }
        return .none
    }

    func color(for role: Role) -> Color {
        switch role {
        case .tonic: NotePalette.color(for: .root)
        case .dominant: NotePalette.color(for: .fifth)
        case .subdominant: NotePalette.color(for: .degree)
        case .none: Color.white.opacity(0.08)
        }
    }

    /// Where a key sits on the ring, in degrees clockwise from the top.
    static func angle(forIndex index: Int) -> Double { Double(index) * 30 }

    // MARK: - The tonic triad

    /// The selected key's tonic triad, on a small board, so the circle stays
    /// connected to the instrument rather than being an abstract diagram.
    var triadPositions: [(position: FretPosition, pitchClass: PitchClass)] {
        let anchor = Positions.findAll(pitchClasses: [selected], tuning: tuning, fretCount: 12)
            .min { ($0.string, $0.fret) < ($1.string, $1.fret) }
        guard let anchor else { return [] }
        return [0, 4, 7].compactMap { semitones in
            let pitchClass = selected.transposed(by: semitones)
            let candidate = Positions.findAll(pitchClasses: [pitchClass], tuning: tuning, fretCount: 12)
                .filter { $0.string >= anchor.string }
                .min { abs($0.fret - anchor.fret) < abs($1.fret - anchor.fret) }
            return candidate.map { (FretPosition(string: $0.string, fret: $0.fret), pitchClass) }
        }
    }

    var dots: [FretboardDot] {
        triadPositions.map { entry in
            FretboardDot(
                id: "circle-\(entry.position.string):\(entry.position.fret)",
                position: entry.position,
                label: entry.pitchClass.name(),
                color: NotePalette.color(for: entry.pitchClass),
                ring: entry.pitchClass == selected ? .white : nil,
                outline: true
            )
        }
    }

    /// The notes of the selected major key.
    var keyNotes: [PitchClass] {
        Harmony.keyScalePitchClasses(root: selected, major: true)
    }

    /// How many notes this key shares with another. Neighbours on the ring
    /// share six of seven; that is the circle's whole point.
    func sharedNoteCount(with other: PitchClass) -> Int {
        let mine = Set(keyNotes.map(\.value))
        let theirs = Set(Harmony.keyScalePitchClasses(root: other, major: true).map(\.value))
        return mine.intersection(theirs).count
    }

    // MARK: - Selection

    func select(_ pitchClass: PitchClass) {
        stop()
        selected = pitchClass
        let value = pitchClass.value
        store?.update { $0.modules.circle.selectedPitchClass = value }
    }

    func step(by delta: Int) {
        select(keys[((selectedIndex + delta) % 12 + 12) % 12])
    }

    func retune(to tuning: Tuning) {
        stop()
        self.tuning = tuning
    }

    // MARK: - Playback

    func strum() {
        let positions = triadPositions.map(\.position)
        guard !positions.isEmpty else { return }
        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer
        sequencer.strum(positions)
        for position in positions { pulse("circle-\(position.string):\(position.fret)") }
    }

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
