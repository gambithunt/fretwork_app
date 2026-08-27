import Foundation
import SwiftUI

/// Harmonizing the scale — building the chords of a key by stacking thirds.
///
/// Ported from `../fretwork/src/lib/modules/Harmonizing.svelte`.
///
/// The lesson is that a key's chords are not a list to memorise: they fall out
/// of the scale. Take a degree, take the note two above it and the note two
/// above that, and the quality — major, minor or diminished — is decided
/// entirely by which scale tones those turn out to be. That is why the module
/// shows the three stacked scale tones next to the chord: the chord is the
/// consequence, and the stack is the reason.
@MainActor
@Observable
final class HarmonizingModuleModel {
    private(set) var keyRoot = PitchClass(0)
    private(set) var isMajor = true
    /// 0...6, I through vii.
    private(set) var degree = 0
    private(set) var pulses: [String: Double] = [:]

    let highestFret = LearningModule.harmonizing.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var sequencer: NoteSequencer?

    init(
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.store = store
        self.play = play
        let saved = store?.state.modules.harmonizing ?? PracticeState.Modules.Harmonizing()
        keyRoot = PitchClass(saved.keyRootPitchClass)
        isMajor = saved.isMajor
        degree = saved.degree
    }

    // MARK: - The key

    var chords: [DiatonicChord] {
        Harmony.diatonicChords(root: keyRoot, major: isMajor)
    }

    var chord: DiatonicChord? {
        chords.indices.contains(degree) ? chords[degree] : chords.first
    }

    var keyName: String { "\(keyRoot.name()) \(isMajor ? "major" : "minor")" }

    /// The three scale tones this chord stacks: the degree, two above, and two
    /// above that. Shown because they are the *reason* the chord is what it is.
    var stackedTones: [PitchClass] {
        let scale = Harmony.keyScalePitchClasses(root: keyRoot, major: isMajor)
        guard scale.count == 7 else { return [] }
        return [0, 2, 4].map { scale[(degree + $0) % 7] }
    }

    // MARK: - The shape

    /// One compact voicing of the chord, chosen nearest the nut so the same
    /// degree always appears in a comparable place as the player steps through
    /// the key.
    var voicing: CompactVoicing? {
        guard let chord, let triad = Triads.triad(short: chord.quality) else { return nil }
        return TriadVoicings.voicings(root: chord.root, triad: triad, fretCount: highestFret)
            .min { $0.minFret < $1.minFret }
    }

    var dots: [FretboardDot] {
        guard let voicing else { return [] }
        return voicing.tones.map { tone in
            FretboardDot(
                id: "harm-\(tone.position.string):\(tone.position.fret)",
                position: FretPosition(string: tone.position.string, fret: tone.position.fret),
                label: tone.degree,
                color: NotePalette.color(for: TriadsModuleModel.role(forDegree: tone.degree)),
                ring: tone.degree == "1" ? .white : nil,
                outline: true
            )
        }
    }

    // MARK: - Selection

    func selectKeyRoot(_ pitchClass: PitchClass) {
        stop()
        keyRoot = pitchClass
        persist()
    }

    func selectMajor(_ major: Bool) {
        stop()
        isMajor = major
        persist()
    }

    func selectDegree(_ degree: Int) {
        guard (0...6).contains(degree) else { return }
        stop()
        self.degree = degree
        persist()
    }

    private func persist() {
        let snapshot = (root: keyRoot.value, major: isMajor, degree: degree)
        store?.update {
            $0.modules.harmonizing.keyRootPitchClass = snapshot.root
            $0.modules.harmonizing.isMajor = snapshot.major
            $0.modules.harmonizing.degree = snapshot.degree
        }
    }

    // MARK: - Playback

    func strum() {
        guard let voicing else { return }
        let positions = voicing.tones
            .sorted { $0.position.string < $1.position.string }
            .map { FretPosition(string: $0.position.string, fret: $0.position.fret) }
        guard !positions.isEmpty else { return }

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer
        sequencer.strum(positions)
        for position in positions { pulse("harm-\(position.string):\(position.fret)") }
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
