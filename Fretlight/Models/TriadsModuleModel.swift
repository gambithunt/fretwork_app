import Foundation
import SwiftUI

/// Triads — three notes stacked in thirds, and how chords are actually built.
///
/// Ported from `../fretwork/src/lib/modules/Triads.svelte`, the largest of the
/// reference modules. It is really two exercises sharing a screen:
///
/// - **Shapes**: one triad (or double-stop) in every compact voicing along the
///   neck, with inversions callable directly. Each tone is coloured by its
///   *role* — root, third, fifth — rather than by its pitch, because the lesson
///   is which degree you are fingering, not which letter it happens to be.
/// - **Paths**: every diatonic triad of a key, voiced on one three-string set,
///   walked up the neck. The set is never left; staying on three adjacent
///   strings while the harmony moves is the whole exercise, and it plays back
///   as a progression.
///
/// Their settings are kept apart in the document on purpose — returning to one
/// should not disturb the other.
@MainActor
@Observable
final class TriadsModuleModel {
    enum View: String, Sendable, CaseIterable {
        case shapes, inversions, doubleStops
    }

    // Shapes
    private(set) var rootPitchClass = PitchClass(0)
    private(set) var triad: ChordDef = Fretwork.Triads.major
    private(set) var doubleStop: DoubleStop = DoubleStops.all[0]
    private(set) var view: View = .shapes
    private(set) var position = 0

    // Paths
    private(set) var isPathMode = false
    private(set) var pathKeyRoot = PitchClass(0)
    private(set) var pathIsMajor = true
    private(set) var pathStringSet: TriadPathStringSet = .dgb
    private(set) var pathStep = 0

    private(set) var pulses: [String: Double] = [:]
    private(set) var progressionSnapshot = ProgressionSession.Snapshot()

    var tuning: Tuning
    let highestFret = LearningModule.triads.highestFret

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
        let saved = store?.state.modules.triads ?? PracticeState.Modules.Triads()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        triad = Fretwork.Triads.all.first { $0.short == saved.triadShort } ?? triad
        doubleStop = DoubleStops.all.first { $0.id == saved.doubleStopID } ?? doubleStop
        view = View(rawValue: saved.view) ?? .shapes
        position = saved.position
        isPathMode = saved.isPathMode
        pathKeyRoot = PitchClass(saved.pathKeyRoot)
        pathIsMajor = saved.pathIsMajor
        pathStringSet = TriadPathStringSet(rawValue: saved.pathStringSet) ?? .dgb
        pathStep = saved.pathStep
    }

    // MARK: - Shapes

    /// Every compact voicing of the current selection, in neck order.
    ///
    /// Note the deliberate omission of `tuning`: `TriadVoicings` builds from
    /// standard string pitches, and `CLAUDE.md` records the rule that a
    /// generator whose output is fixed fret offsets must not accept a `Tuning`
    /// it cannot honour. Voicings are therefore shown in standard tuning only,
    /// which is what the web does too.
    var voicings: [CompactVoicing] {
        switch view {
        case .doubleStops:
            DoubleStops.all.first { $0.id == doubleStop.id }
                .map { TriadVoicings.doubleStopVoicings(root: rootPitchClass, definition: $0, fretCount: highestFret) } ?? []
        case .shapes, .inversions:
            TriadVoicings.voicings(root: rootPitchClass, triad: triad, fretCount: highestFret)
        }
    }

    var currentVoicing: CompactVoicing? {
        let all = voicings
        guard !all.isEmpty else { return nil }
        return all[min(max(position, 0), all.count - 1)]
    }

    /// The inversions available for the current triad, in the order the web
    /// lists them.
    static let inversionOrder = ["Root position", "1st inversion", "2nd inversion"]

    var availableInversions: [String] {
        let present = Set(voicings.map(\.inversion))
        return Self.inversionOrder.filter(present.contains)
    }

    var selectedInversion: String? { currentVoicing?.inversion }

    // MARK: - Paths

    var pathSteps: [TriadPathStep] {
        TriadPaths.diatonicPath(keyRoot: pathKeyRoot, major: pathIsMajor, stringSet: pathStringSet)
    }

    var currentPathStep: TriadPathStep? {
        let steps = pathSteps
        guard !steps.isEmpty else { return nil }
        return steps[min(max(pathStep, 0), steps.count - 1)]
    }

    /// The voicing on screen, whichever exercise is running.
    var activeVoicing: CompactVoicing? {
        isPathMode ? currentPathStep?.voicing : currentVoicing
    }

    // MARK: - Dots

    /// Coloured by degree, not by pitch. In this module a note's job — root,
    /// third, fifth — is the subject, and the third is what decides whether the
    /// chord is major or minor.
    static func role(forDegree degree: String) -> NotePalette.Role {
        if degree.hasSuffix("1") { return .root }
        if degree.hasSuffix("3") { return .third }
        if degree.hasSuffix("5") { return .fifth }
        return .degree
    }

    var dots: [FretboardDot] {
        guard let voicing = activeVoicing else { return [] }
        return voicing.tones.map { tone in
            FretboardDot(
                id: "triad-\(tone.position.string):\(tone.position.fret)",
                position: FretPosition(string: tone.position.string, fret: tone.position.fret),
                label: tone.degree,
                color: NotePalette.color(for: Self.role(forDegree: tone.degree)),
                ring: tone.degree == "1" ? .white : nil,
                outline: true
            )
        }
    }

    // MARK: - Selection

    func selectRoot(_ pitchClass: PitchClass) {
        stopEverything()
        if isPathMode {
            pathKeyRoot = pitchClass
            pathStep = 0
        } else {
            rootPitchClass = pitchClass
            position = 0
        }
        persist()
    }

    func selectTriad(_ triad: ChordDef) {
        stopEverything()
        self.triad = triad
        if view == .doubleStops { view = .shapes }
        position = 0
        persist()
    }

    func selectDoubleStop(_ doubleStop: DoubleStop) {
        stopEverything()
        self.doubleStop = doubleStop
        view = .doubleStops
        position = 0
        persist()
    }

    func selectView(_ view: View) {
        stopEverything()
        self.view = view
        // Inversions are a way of reading the same voicings, so entering that
        // view starts from root position rather than wherever the player was.
        if view == .inversions,
           let index = voicings.firstIndex(where: { $0.inversion == "Root position" }) {
            position = index
        }
        persist()
    }

    func selectInversion(_ inversion: String) {
        guard let index = voicings.firstIndex(where: { $0.inversion == inversion }) else { return }
        stopEverything()
        position = index
        persist()
    }

    func movePosition(by delta: Int) {
        let all = voicings
        guard !all.isEmpty else { return }
        stopEverything()
        position = ((position + delta) % all.count + all.count) % all.count
        persist()
    }

    // MARK: - Path selection

    func setPathMode(_ enabled: Bool) {
        stopEverything()
        isPathMode = enabled
        persist()
    }

    func selectPathStringSet(_ stringSet: TriadPathStringSet) {
        stopEverything()
        pathStringSet = stringSet
        pathStep = 0
        persist()
    }

    func setPathMajor(_ major: Bool) {
        stopEverything()
        pathIsMajor = major
        pathStep = 0
        persist()
    }

    func selectPathStep(_ index: Int) {
        let steps = pathSteps
        guard steps.indices.contains(index) else { return }
        stopEverything()
        pathStep = index
        persist()
    }

    func retune(to tuning: Tuning) {
        stopEverything()
        self.tuning = tuning
    }

    private func persist() {
        let snapshot = (
            root: rootPitchClass.value, triadShort: triad.short, doubleStopID: doubleStop.id,
            view: view.rawValue, position: position, pathKeyRoot: pathKeyRoot.value,
            pathIsMajor: pathIsMajor, pathStringSet: pathStringSet.rawValue,
            pathStep: pathStep, isPathMode: isPathMode
        )
        store?.update {
            $0.modules.triads.rootPitchClass = snapshot.root
            $0.modules.triads.triadShort = snapshot.triadShort
            $0.modules.triads.doubleStopID = snapshot.doubleStopID
            $0.modules.triads.view = snapshot.view
            $0.modules.triads.position = snapshot.position
            $0.modules.triads.pathKeyRoot = snapshot.pathKeyRoot
            $0.modules.triads.pathIsMajor = snapshot.pathIsMajor
            $0.modules.triads.pathStringSet = snapshot.pathStringSet
            $0.modules.triads.pathStep = snapshot.pathStep
            $0.modules.triads.isPathMode = snapshot.isPathMode
        }
    }

    // MARK: - Playback

    /// Strums the voicing on screen, low string first, as a hand would.
    func playVoicing() {
        guard let voicing = activeVoicing else { return }
        let positions = voicing.tones
            .sorted { $0.position.string < $1.position.string }
            .map { FretPosition(string: $0.position.string, fret: $0.position.fret) }

        let sequencer = sequencer ?? makeSequencer()
        self.sequencer = sequencer
        sequencer.strum(positions)
        for position in positions { pulse("triad-\(position.string):\(position.fret)") }
    }

    /// Walks the diatonic path as a progression, one chord per bar, lighting
    /// each shape as it sounds — the callback that keeps what is heard and what
    /// is shown from drifting apart.
    func startProgression(loop: Bool) {
        let steps = pathSteps
        guard isPathMode, !steps.isEmpty else { return }
        stopEverything()

        let session = ProgressionSession(
            onState: { [weak self] snapshot in
                Task { @MainActor [weak self] in self?.progressionSnapshot = snapshot }
            },
            onStep: { [weak self] index, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.pathSteps.indices.contains(index) else { return }
                    self.pathStep = index
                    self.playVoicing()
                }
            }
        )
        progression = session
        session.startProgression(total: steps.count, loop: loop, beatsPerStep: 4)
        // Taken synchronously as well as through `onState`. The callback hops
        // to the main actor, so without this the UI — and a test — would still
        // see `idle` immediately after starting, which reads as the button not
        // having worked.
        progressionSnapshot = session.snapshot
    }

    func stopProgression() {
        progression?.stop()
        progressionSnapshot = ProgressionSession.Snapshot()
    }

    @discardableResult func slower() -> Int { progression?.slower() ?? ProgressionSession.defaultTempoBpm }
    @discardableResult func faster() -> Int { progression?.faster() ?? ProgressionSession.defaultTempoBpm }

    private func makeSequencer() -> NoteSequencer {
        NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
    }

    /// Any selection change stops both engines. A progression that kept running
    /// after the key changed would be playing the previous key's chords over
    /// the new key's shapes.
    func stopEverything() {
        stopProgression()
        stop()
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
