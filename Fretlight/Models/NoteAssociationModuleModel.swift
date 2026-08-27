import Foundation
import SwiftUI

/// Note association — the capstone.
///
/// Ported from `../fretwork/src/lib/modules/NoteAssociation.svelte`. It puts
/// the other modules on one neck at once: the chord tones you are playing over,
/// the pentatonic you would solo with, and the rest of the scale behind both.
///
/// **The layering is the lesson.** A note is not simply "in the key" — it has a
/// job relative to the chord sounding right now, and that job changes as the
/// progression moves while the notes stay put. So one pitch can be a chord tone
/// in one bar and a passing note in the next, and the board shows that by
/// re-colouring rather than by moving anything.
///
/// Each layer can be turned off, because seeing the scale alone, or the chord
/// tones alone, is a different exercise from seeing all three.
@MainActor
@Observable
final class NoteAssociationModuleModel {
    enum LabelMode: String, Sendable { case notes, degrees }

    private(set) var keyRoot = PitchClass(0)
    private(set) var isMajor = true
    /// 0...6 — which chord of the key is in focus when nothing is playing.
    private(set) var selectedDegree = 0
    private(set) var progressionID: ProgressionID = .pop1564
    private(set) var loop = false
    private(set) var labelMode: LabelMode = .notes
    private(set) var showsChordTones = true
    private(set) var showsPentatonic = true
    private(set) var showsScale = true

    private(set) var pulses: [String: Double] = [:]
    private(set) var progressionSnapshot = ProgressionSession.Snapshot()
    /// Set while a progression is playing; nil otherwise.
    private(set) var playingDegree: Int?

    var tuning: Tuning
    let highestFret = LearningModule.noteAssociation.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var sequencer: NoteSequencer?
    private var progression: ProgressionSession?

    init(
        tuning: Tuning = Tunings.standard,
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.tuning = tuning
        self.store = store
        self.play = play
        let saved = store?.state.modules.noteAssociation ?? PracticeState.Modules.NoteAssociation()
        keyRoot = PitchClass(saved.rootPitchClass)
        isMajor = saved.isMajor
        selectedDegree = saved.chordDegree
        progressionID = ProgressionID(rawValue: saved.progressionID) ?? .pop1564
        loop = saved.loop
        labelMode = LabelMode(rawValue: saved.labelMode) ?? .notes
        showsChordTones = saved.showsChordTones
        showsPentatonic = saved.showsPentatonic
        showsScale = saved.showsScale
    }

    // MARK: - The key

    var chords: [DiatonicChord] { Harmony.diatonicChords(root: keyRoot, major: isMajor) }

    /// While a progression plays, the focus follows it — the whole point is to
    /// watch the roles change under your fingers as the chord moves.
    var focusedDegree: Int { playingDegree ?? selectedDegree }

    var chord: DiatonicChord? {
        chords.indices.contains(focusedDegree) ? chords[focusedDegree] : chords.first
    }

    var keyName: String { "\(keyRoot.name()) \(isMajor ? "major" : "minor")" }

    var scaleNotes: [PitchClass] { Harmony.keyScalePitchClasses(root: keyRoot, major: isMajor) }
    var pentatonicNotes: [PitchClass] { Harmony.keyPentatonicPitchClasses(root: keyRoot, major: isMajor) }

    var progressions: [Progression] {
        Progressions.all.filter { $0.applicableModes.contains(KeyMode(major: isMajor)) }
    }

    var progressionChords: [DiatonicChord] {
        Progressions.resolve(root: keyRoot, major: isMajor, progressionID: progressionID)
    }

    // MARK: - Roles

    /// What a pitch is doing relative to the chord in focus. Ordered by
    /// precedence: a chord tone is a chord tone even if it is also in the
    /// pentatonic, because that is the stronger fact while this chord sounds.
    enum Role: Equatable {
        case chordTone(String)
        case pentatonic
        case scale
        case outside
    }

    func role(of pitchClass: PitchClass) -> Role {
        if let chord, let index = chord.pitchClasses.firstIndex(of: pitchClass) {
            return .chordTone(chord.degrees.indices.contains(index) ? chord.degrees[index] : "1")
        }
        if pentatonicNotes.contains(pitchClass) { return .pentatonic }
        if scaleNotes.contains(pitchClass) { return .scale }
        return .outside
    }

    /// Whether a role is currently drawn, given which layers are on.
    func isVisible(_ role: Role) -> Bool {
        switch role {
        case .chordTone: showsChordTones
        case .pentatonic: showsPentatonic
        case .scale: showsScale
        case .outside: false
        }
    }

    private func color(for role: Role) -> Color {
        switch role {
        case .chordTone(let degree): NotePalette.color(for: TriadsModuleModel.role(forDegree: degree))
        case .pentatonic: NotePalette.color(for: .pentatonic)
        case .scale: NotePalette.color(for: .outsideShape)
        case .outside: .clear
        }
    }

    // MARK: - Dots

    var dots: [FretboardDot] {
        var dots: [FretboardDot] = []
        for string in tuning.openMIDINotes.indices {
            for fret in 0...highestFret {
                let pitchClass = PitchClass(tuning.openMIDINotes[string] + fret)
                let role = role(of: pitchClass)
                guard isVisible(role) else { continue }

                let isChordTone = { if case .chordTone = role { return true } else { return false } }()
                let label: String
                switch (labelMode, role) {
                case (.degrees, .chordTone(let degree)): label = degree
                case (.degrees, _): label = degreeInKey(pitchClass)
                default: label = pitchClass.name()
                }

                dots.append(FretboardDot(
                    id: "na-\(string):\(fret)",
                    position: FretPosition(string: string, fret: fret),
                    label: label,
                    color: color(for: role),
                    radius: isChordTone ? FretboardDot.defaultRadius : 10,
                    alpha: isChordTone ? 1 : (role == .pentatonic ? 0.7 : 0.4),
                    // A pentatonic note that is also a chord tone keeps its
                    // chord colour and gains a ring, so both facts are visible
                    // at once rather than one hiding the other.
                    ring: isChordTone && showsPentatonic && pentatonicNotes.contains(pitchClass)
                        ? NotePalette.color(for: .pentatonic) : nil,
                    ringAlpha: 0.55,
                    outline: isChordTone
                ))
            }
        }
        return dots
    }

    /// The pitch's degree within the key, for the degrees label mode.
    func degreeInKey(_ pitchClass: PitchClass) -> String {
        guard let index = scaleNotes.firstIndex(of: pitchClass) else { return "" }
        let scale = isMajor ? Scales.major : Scales.naturalMinor
        return scale.degrees.indices.contains(index) ? scale.degrees[index] : ""
    }

    // MARK: - Selection

    func selectKeyRoot(_ pitchClass: PitchClass) {
        stopEverything()
        keyRoot = pitchClass
        persist()
    }

    func selectMajor(_ major: Bool) {
        stopEverything()
        isMajor = major
        // A progression written for the other mode does not resolve, so fall
        // back to one that does rather than showing an empty bar.
        if !progressions.contains(where: { $0.id == progressionID }) {
            progressionID = progressions.first?.id ?? progressionID
        }
        persist()
    }

    func selectDegree(_ degree: Int) {
        guard (0...6).contains(degree) else { return }
        stopEverything()
        selectedDegree = degree
        persist()
    }

    func selectProgression(_ id: ProgressionID) {
        stopEverything()
        progressionID = id
        persist()
    }

    func setLoop(_ loop: Bool) {
        self.loop = loop
        persist()
    }

    func setLabelMode(_ mode: LabelMode) {
        // A view change, not a change of what is being practised — so it does
        // not stop playback, same as Scales.
        labelMode = mode
        persist()
    }

    func setLayer(chordTones: Bool? = nil, pentatonic: Bool? = nil, scale: Bool? = nil) {
        if let chordTones { showsChordTones = chordTones }
        if let pentatonic { showsPentatonic = pentatonic }
        if let scale { showsScale = scale }
        persist()
    }

    func retune(to tuning: Tuning) {
        stopEverything()
        self.tuning = tuning
    }

    private func persist() {
        let snapshot = (
            root: keyRoot.value, major: isMajor, degree: selectedDegree,
            progression: progressionID.rawValue, loop: loop, label: labelMode.rawValue,
            chordTones: showsChordTones, pentatonic: showsPentatonic, scale: showsScale
        )
        store?.update {
            $0.modules.noteAssociation.rootPitchClass = snapshot.root
            $0.modules.noteAssociation.isMajor = snapshot.major
            $0.modules.noteAssociation.chordDegree = snapshot.degree
            $0.modules.noteAssociation.progressionID = snapshot.progression
            $0.modules.noteAssociation.loop = snapshot.loop
            $0.modules.noteAssociation.labelMode = snapshot.label
            $0.modules.noteAssociation.showsChordTones = snapshot.chordTones
            $0.modules.noteAssociation.showsPentatonic = snapshot.pentatonic
            $0.modules.noteAssociation.showsScale = snapshot.scale
        }
    }

    // MARK: - Playback

    /// Strums the focused chord where it sits nearest the nut.
    func strumChord() {
        guard let chord, let triad = Triads.triad(short: chord.quality),
              let voicing = TriadVoicings.voicings(root: chord.root, triad: triad, fretCount: highestFret)
                  .min(by: { $0.minFret < $1.minFret })
        else { return }

        let positions = voicing.tones
            .sorted { $0.position.string < $1.position.string }
            .map { FretPosition(string: $0.position.string, fret: $0.position.fret) }

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer
        sequencer.strum(positions)
    }

    /// Walks the progression, moving the focus with it so the roles re-colour
    /// under the player's fingers while the notes stay where they are.
    func startProgression() {
        let steps = progressionChords
        guard !steps.isEmpty else { return }
        stopEverything()

        let beats = Progressions.progression(id: progressionID).beatsPerChord
        let degrees = Progressions.progression(id: progressionID).degrees
        let session = ProgressionSession(
            onState: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progressionSnapshot = snapshot
                    if snapshot.status == .idle { self.playingDegree = nil }
                }
            },
            onStep: { [weak self] index, _ in
                Task { @MainActor [weak self] in
                    guard let self, degrees.indices.contains(index) else { return }
                    self.playingDegree = degrees[index]
                    self.strumChord()
                }
            }
        )
        progression = session
        session.startProgression(total: steps.count, loop: loop, beatsPerStep: beats)
        progressionSnapshot = session.snapshot
    }

    func stopEverything() {
        progression?.stop()
        progressionSnapshot = ProgressionSession.Snapshot()
        playingDegree = nil
        sequencer?.stop()
        pulses.removeAll()
    }
}
