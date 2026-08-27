import Foundation
import SwiftUI

/// Scales — one-octave major and natural-minor shapes, with fingerings and
/// guided practice.
///
/// Ported from `../fretwork/src/lib/modules/Scales.svelte`.
///
/// **This one does take a tuning**, unlike Pentatonic and Chords.
/// `ScaleShapes.oneOctaveScale` derives every note from MIDI rather than from
/// fixed fret offsets, so it transposes honestly when the strings are tuned
/// differently. That difference is the reason the two generators have different
/// signatures, and `CLAUDE.md` records why one must not accept a `Tuning` it
/// cannot honour.
@MainActor
@Observable
final class ScalesModuleModel {
    enum LabelMode: String, Sendable, CaseIterable {
        /// What the note is — for learning the neck.
        case notes
        /// What the note does — for learning the scale.
        case degrees
    }

    enum Direction: String, Sendable, CaseIterable {
        case ascending, upDown
    }

    private(set) var rootPitchClass = PitchClass(0)
    private(set) var quality: OneOctaveScaleQuality = .major
    private(set) var labelMode: LabelMode = .notes
    private(set) var direction: Direction = .ascending
    private(set) var guidedSnapshot = GuidedSession<GuidedScaleStep>.Snapshot()
    private(set) var currentStep: GuidedScaleStep?

    var tuning: Tuning
    let highestFret = LearningModule.scales.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var guided: GuidedSession<GuidedScaleStep>?

    init(
        tuning: Tuning = Tunings.standard,
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.tuning = tuning
        self.store = store
        self.play = play
        let saved = store?.state.modules.scales ?? PracticeState.Modules.Scales()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        quality = OneOctaveScaleQuality(rawValue: saved.quality) ?? .major
        labelMode = LabelMode(rawValue: saved.labelMode) ?? .notes
        direction = Direction(rawValue: saved.direction) ?? .ascending
    }

    // MARK: - The shape

    /// The eight notes of the octave: seven degrees plus the root again on top,
    /// which is what makes it sound finished.
    var steps: [GuidedScaleStep] {
        ScaleShapes.oneOctaveScale(root: rootPitchClass, quality: quality, tuning: tuning)
    }

    /// What a guided run walks: up, or up and back down without repeating the
    /// top note.
    var sequence: [GuidedScaleStep] {
        ScaleShapes.buildScaleSequence(steps, upDown: direction == .upDown)
    }

    var scaleName: String {
        "\(rootPitchClass.name()) \(quality == .major ? "major" : "natural minor")"
    }

    // MARK: - Dots

    var dots: [FretboardDot] {
        let base = steps.map { step -> FretboardDot in
            let isRoot = step.pitchClass == rootPitchClass
            return FretboardDot(
                id: step.id,
                position: FretPosition(string: step.string, fret: step.fret),
                label: labelMode == .notes ? step.pitchClass.name() : step.degree,
                // Pitch keeps its own colour, as the web does — the shared note
                // palette is the app's identity for a pitch, and the degree is
                // carried by the label instead.
                color: NotePalette.color(for: step.pitchClass),
                ring: isRoot ? .white : nil,
                outline: true
            )
        }
        // `sequence`, not `steps`: the snapshot's index counts positions in the
        // run, and an up-and-down run is longer than the shape. Indexing the
        // shape would emphasise the wrong note on the way back down — or none
        // at all, since the index runs past its end.
        return GuidedPresentation.decorate(base, steps: sequence, snapshot: guidedSnapshot)
    }

    // MARK: - Selection

    func selectRoot(_ pitchClass: PitchClass) {
        stopGuided()
        rootPitchClass = pitchClass
        persist()
    }

    func selectQuality(_ quality: OneOctaveScaleQuality) {
        stopGuided()
        self.quality = quality
        persist()
    }

    func selectLabelMode(_ mode: LabelMode) {
        // Deliberately does *not* stop a run: relabelling is a change of view,
        // not of what is being practised, and interrupting a run to read the
        // degrees instead of the notes would be hostile.
        labelMode = mode
        persist()
    }

    func selectDirection(_ direction: Direction) {
        stopGuided()
        self.direction = direction
        persist()
    }

    func retune(to tuning: Tuning) {
        stopGuided()
        self.tuning = tuning
    }

    private func persist() {
        let snapshot = (root: rootPitchClass.value, quality: quality.rawValue,
                        label: labelMode.rawValue, direction: direction.rawValue)
        store?.update {
            $0.modules.scales.rootPitchClass = snapshot.root
            $0.modules.scales.quality = snapshot.quality
            $0.modules.scales.labelMode = snapshot.label
            $0.modules.scales.direction = snapshot.direction
        }
    }

    // MARK: - Guided practice

    func startGuided() {
        let run = sequence
        guard !run.isEmpty else { return }
        stopGuided()

        let session = GuidedSession<GuidedScaleStep>(
            onState: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.guidedSnapshot = snapshot
                    if snapshot.status == .idle { self.currentStep = nil }
                }
            },
            onStep: { [weak self] step, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentStep = step
                    self.play(FretPosition(string: step.string, fret: step.fret))
                }
            }
        )
        guided = session
        session.start(run)
        guidedSnapshot = session.snapshot
    }

    func stopGuided() {
        guided?.stop()
        guidedSnapshot = GuidedSession<GuidedScaleStep>.Snapshot()
        currentStep = nil
    }

    @discardableResult func slower() -> Int { guided?.slower() ?? GuidedSession<GuidedScaleStep>.defaultTempoBpm }
    @discardableResult func faster() -> Int { guided?.faster() ?? GuidedSession<GuidedScaleStep>.defaultTempoBpm }

    var nextStep: GuidedScaleStep? {
        guard let index = guidedSnapshot.currentIndex else { return nil }
        let run = sequence
        return run.indices.contains(index + 1) ? run[index + 1] : nil
    }
}
