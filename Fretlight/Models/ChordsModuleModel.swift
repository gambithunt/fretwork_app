import Foundation
import SwiftUI

/// Major, minor and power chords — movable shapes traced back to the degrees
/// they are built from.
///
/// Ported from `../fretwork/src/lib/modules/Chords.svelte`. The selector is two
/// levels deep on purpose: a family (core, sevenths, colour, extensions) and
/// then a formula inside it. Sixteen formulas in one flat list is a wall; the
/// families are how a player finds the one they mean.
///
/// **Muted strings are content, not absence.** A voicing's `frets` carries `nil`
/// for a string the conventional shape does not sound, and a chord diagram that
/// silently omitted them would teach a shape you cannot actually strum. They are
/// reported separately so the screen can mark them.
///
/// Standard tuning only. `ChordVoicings` holds fixed fret shapes, and
/// `CLAUDE.md` records the rule: a generator whose output is fixed fret offsets
/// must not accept a `Tuning` it cannot honour, because those frets do not
/// transpose — they detune.
@MainActor
@Observable
final class ChordsModuleModel {
    private(set) var rootPitchClass = PitchClass(0)
    private(set) var formula: ChordFormula = ChordFormulas.all[0]
    private(set) var positionID = ""
    private(set) var pulses: [String: Double] = [:]

    let highestFret = LearningModule.chords.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var sequencer: NoteSequencer?

    init(
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.store = store
        self.play = play
        let saved = store?.state.modules.chords ?? PracticeState.Modules.Chords()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        formula = ChordFormulas.formula(id: saved.formulaID) ?? formula
        positionID = saved.positionID
    }

    // MARK: - Selection surface

    static let families: [ChordFamilyId] = [.core, .sevenths, .colour, .extensions]

    static func label(for family: ChordFamilyId) -> String {
        switch family {
        case .core: "Core"
        case .sevenths: "Sevenths"
        case .colour: "Colour"
        case .extensions: "Extensions"
        }
    }

    var family: ChordFamilyId { formula.family }

    /// The formulas inside the current family — the second level of the
    /// selector.
    var formulasInFamily: [ChordFormula] {
        ChordFormulas.all.filter { $0.family == family }
    }

    /// How the chord is written: `C`, `Cm`, `C5`, `Cmaj7`.
    var symbol: String { "\(rootPitchClass.name())\(formula.suffix)" }

    // MARK: - Voicings

    var voicings: [ChordVoicing] {
        ChordVoicings.voicings(root: rootPitchClass, formulaID: formula.id)
    }

    var currentVoicing: ChordVoicing? {
        let all = voicings
        guard !all.isEmpty else { return nil }
        return all.first { $0.id == positionID } ?? all.first
    }

    var positionIndex: Int? {
        guard let voicing = currentVoicing else { return nil }
        return voicings.firstIndex { $0.id == voicing.id }
    }

    /// "Open", "Fret 5", or "Frets 5–8" — where the hand goes.
    var positionLabel: String {
        guard let voicing = currentVoicing else { return "—" }
        if voicing.isOpen { return "Open" }
        if voicing.minFret == voicing.maxFret { return "Fret \(voicing.minFret)" }
        return "Frets \(voicing.minFret)–\(voicing.maxFret)"
    }

    /// Strings the shape deliberately does not sound.
    var mutedStrings: [Int] {
        guard let voicing = currentVoicing else { return [] }
        return voicing.frets.enumerated().compactMap { $1 == nil ? $0 : nil }
    }

    // MARK: - Dots

    /// Which degree a sounded string is contributing, so the shape can be read
    /// as a chord rather than memorised as finger positions.
    func degree(forString string: Int, fret: Int) -> String {
        let midi = Tunings.standard.openMIDINotes[string] + fret
        let distance = PitchClass(midi - rootPitchClass.value).value
        // Compared modulo an octave because an extension is written above the
        // octave — a 9th is interval 14 in some spellings and 2 in others, and
        // both name the same note on the neck.
        guard let index = formula.intervals.firstIndex(where: { PitchClass($0).value == distance }) else { return "?" }
        return formula.degrees[index]
    }

    var dots: [FretboardDot] {
        guard let voicing = currentVoicing else { return [] }
        return voicing.frets.enumerated().compactMap { string, fret in
            guard let fret else { return nil }
            let degree = degree(forString: string, fret: fret)
            return FretboardDot(
                id: "chord-\(string)",
                position: FretPosition(string: string, fret: fret),
                label: degree,
                color: NotePalette.color(for: TriadsModuleModel.role(forDegree: degree)),
                ring: degree == "1" ? .white : nil,
                outline: true
            )
        }
    }

    // MARK: - Choosing

    func selectRoot(_ pitchClass: PitchClass) {
        stop()
        rootPitchClass = pitchClass
        snapToLowestPosition()
        persist()
    }

    /// Switching family moves to that family's first formula, since the
    /// formula that was selected does not exist in the new one.
    func selectFamily(_ family: ChordFamilyId) {
        guard let first = ChordFormulas.all.first(where: { $0.family == family }) else { return }
        selectFormula(first)
    }

    func selectFormula(_ formula: ChordFormula) {
        stop()
        self.formula = formula
        snapToLowestPosition()
        persist()
    }

    func selectPosition(id: String) {
        guard voicings.contains(where: { $0.id == id }) else { return }
        stop()
        positionID = id
        persist()
    }

    func movePosition(by delta: Int) {
        let all = voicings
        guard !all.isEmpty, let index = positionIndex else { return }
        stop()
        positionID = all[((index + delta) % all.count + all.count) % all.count].id
        persist()
    }

    /// A saved position belongs to the previous root or formula, so changing
    /// either starts from the shape nearest the nut — where a player looking
    /// for a new chord expects to begin.
    private func snapToLowestPosition() {
        positionID = ChordVoicings.lowestPositionID(root: rootPitchClass, formulaID: formula.id)
            ?? voicings.first?.id ?? ""
    }

    private func persist() {
        let root = rootPitchClass.value
        let formulaID = formula.id
        let position = positionID
        store?.update {
            $0.modules.chords.rootPitchClass = root
            $0.modules.chords.formulaID = formulaID
            $0.modules.chords.positionID = position
        }
    }

    // MARK: - Playback

    /// Strummed low to high, skipping the muted strings — which is what makes
    /// the mute audible as part of the shape rather than a gap.
    func strum() {
        guard let voicing = currentVoicing else { return }
        let positions = voicing.frets.enumerated().compactMap { string, fret in
            fret.map { FretPosition(string: string, fret: $0) }
        }
        guard !positions.isEmpty else { return }

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer
        sequencer.strum(positions)
        for position in positions { pulse("chord-\(position.string)") }
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
