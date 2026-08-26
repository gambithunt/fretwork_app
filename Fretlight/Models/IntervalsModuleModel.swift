import Foundation
import SwiftUI

/// Intervals — a root plus one related note, anchored somewhere on the neck.
///
/// Ported from `../fretwork/src/lib/modules/Intervals.svelte`. The module's
/// point is that an interval is a *shape under the hand*, not an abstraction:
/// the same fifth is a different physical move depending on which string the
/// root is on, so the board shows every root you could anchor on, dimmed, and
/// lights up the one you have chosen along with the notes it reaches.
@MainActor
@Observable
final class IntervalsModuleModel {
    private(set) var rootPitchClass = PitchClass(0)
    private(set) var interval: Interval = Intervals.all.first { $0.short == "P5" } ?? Intervals.all[0]
    /// `"string:fret"` of the chosen root position.
    private(set) var anchorKey = "1:3"
    private(set) var pulses: [String: Double] = [:]
    /// Which of the interval's uses the player has expanded, if any.
    var selectedUseIndex: Int?

    var tuning: Tuning
    let highestFret = LearningModule.intervals.highestFret

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
        let saved = store?.state.modules.intervals ?? PracticeState.Modules.Intervals()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        interval = Intervals.all.first { $0.short == saved.intervalShort } ?? interval
        anchorKey = saved.anchor
    }

    // MARK: - Anchors

    var anchors: [IntervalAnchor] {
        IntervalShapes.anchors(
            root: rootPitchClass,
            semitones: interval.semitones,
            tuning: tuning,
            fretCount: highestFret
        )
    }

    var playableAnchors: [IntervalAnchor] { anchors.filter(\.isPlayable) }

    static func key(_ position: NeckPosition) -> String { "\(position.string):\(position.fret)" }

    private var preferredPosition: NeckPosition? {
        let parts = anchorKey.split(separator: ":")
        guard parts.count == 2, let string = Int(parts[0]), let fret = Int(parts[1]) else { return nil }
        return NeckPosition(string: string, fret: fret, midiNote: 0, pitchClass: rootPitchClass)
    }

    /// The anchor currently in play. Resolved rather than looked up: a saved
    /// anchor may be unreachable after a change of root, interval or tuning, and
    /// falling back to the nearest playable one keeps the board meaningful
    /// instead of blank.
    var activeAnchor: IntervalAnchor? {
        guard let preferred = preferredPosition else { return playableAnchors.first }
        return IntervalShapes.resolve(anchors: anchors, preferred: preferred)
    }

    /// The target that is actually comfortable to reach from the root — the
    /// closest one, weighting a string change as worth two frets, which is the
    /// web's own measure of "practical".
    var practicalTarget: NeckPosition? {
        guard let anchor = activeAnchor, !anchor.targets.isEmpty else { return nil }
        return anchor.targets.min {
            Self.reach(from: anchor.root, to: $0) < Self.reach(from: anchor.root, to: $1)
        }
    }

    private static func reach(from root: NeckPosition, to target: NeckPosition) -> Int {
        abs(target.fret - root.fret) + abs(target.string - root.string) * 2
    }

    var targetPitchClass: PitchClass { rootPitchClass.transposed(by: interval.semitones) }

    // MARK: - Dots

    /// Three tiers, and the tiering is the teaching: every root you *could*
    /// anchor on sits recessed, the chosen root is full size, and the notes it
    /// reaches are marked in the interval's own colour rather than the note's,
    /// because here they mean "a fifth away" rather than "a G".
    var dots: [FretboardDot] {
        let anchors = self.anchors
        let active = activeAnchor
        let targetKeys = Set((active?.targets ?? []).map(Self.key))

        var dots: [FretboardDot] = []

        for anchor in anchors where Self.key(anchor.root) != active.map({ Self.key($0.root) }) && !targetKeys.contains(Self.key(anchor.root)) {
            dots.append(FretboardDot(
                id: "root-option-\(Self.key(anchor.root))",
                position: FretPosition(string: anchor.root.string, fret: anchor.root.fret),
                label: rootPitchClass.name(),
                color: NotePalette.color(for: anchor.root.pitchClass),
                radius: anchor.isPlayable ? 9 : 7,
                alpha: anchor.isPlayable ? 0.48 : 0.2
            ))
        }

        if let active {
            for target in active.targets {
                dots.append(FretboardDot(
                    id: "target-\(Self.key(target))",
                    position: FretPosition(string: target.string, fret: target.fret),
                    label: interval.short,
                    color: NotePalette.color(for: .third),
                    ring: Self.key(target) == practicalTarget.map(Self.key) ? .white : nil,
                    outline: true
                ))
            }
            dots.append(FretboardDot(
                id: "root-\(Self.key(active.root))",
                position: FretPosition(string: active.root.string, fret: active.root.fret),
                label: rootPitchClass.name(),
                color: NotePalette.color(for: .root),
                outline: true
            ))
        }
        return dots
    }

    /// The exercise text with `{root}` and `{target}` filled in.
    var exercise: String {
        interval.exercise
            .replacingOccurrences(of: "{root}", with: rootPitchClass.name())
            .replacingOccurrences(of: "{target}", with: targetPitchClass.name())
    }

    // MARK: - Selection

    func selectRoot(_ pitchClass: PitchClass) {
        stop()
        rootPitchClass = pitchClass
        selectedUseIndex = nil
        reanchor()
        persist()
    }

    func selectInterval(_ interval: Interval) {
        stop()
        self.interval = interval
        selectedUseIndex = nil
        reanchor()
        persist()
    }

    /// Anchoring on a tapped root is the module's main interaction: the same
    /// interval, moved under a different finger.
    func selectAnchor(string: Int, fret: Int) {
        let candidate = NeckPosition(string: string, fret: fret, midiNote: 0, pitchClass: rootPitchClass)
        guard let resolved = IntervalShapes.resolve(anchors: anchors, preferred: candidate) else { return }
        stop()
        anchorKey = Self.key(resolved.root)
        persist()
    }

    /// After a change of root, interval or tuning the saved anchor may not
    /// exist any more. Snapping to whatever is nearest keeps the board showing
    /// a real shape.
    private func reanchor() {
        guard let active = activeAnchor else { return }
        anchorKey = Self.key(active.root)
    }

    /// Called when the tuning changes: every anchor moves, so the saved one has
    /// to be re-resolved.
    func retune(to tuning: Tuning) {
        stop()
        self.tuning = tuning
        reanchor()
        persist()
    }

    private func persist() {
        let root = rootPitchClass.value
        let short = interval.short
        let anchor = anchorKey
        store?.update {
            $0.modules.intervals.rootPitchClass = root
            $0.modules.intervals.intervalShort = short
            $0.modules.intervals.anchor = anchor
        }
    }

    // MARK: - Playback

    /// Root, then the interval, then both — the way you check an interval by
    /// ear: hear the distance, then hear it as one sound.
    func playInterval() {
        guard let anchor = activeAnchor, let target = practicalTarget else { return }
        let rootPosition = FretPosition(string: anchor.root.string, fret: anchor.root.fret)
        let targetPosition = FretPosition(string: target.string, fret: target.fret)

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer

        var options = NoteSequencer.Options()
        options.gap = 0.6
        options.strumTogether = true
        options.onHit = { [weak self] position, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pulse(position == rootPosition ? "root-\(Self.key(anchor.root))" : "target-\(Self.key(target))")
            }
        }
        sequencer.play([rootPosition, targetPosition], options: options)
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
