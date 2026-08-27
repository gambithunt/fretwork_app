import Foundation
import SwiftUI

/// Octaves — the same note higher on the neck, as a movable two-string shape.
///
/// Ported from `../fretwork/src/lib/modules/Octaves.svelte`.
///
/// **The fret offset is tuning-honest, and that is the whole lesson.** In
/// standard tuning the octave shape is "two strings up, two frets across" —
/// except across the G–B string pair, where the major-third gap makes it three.
/// A module that drew a fixed +2 everywhere would teach a shape that is wrong on
/// a third of the neck, so the offset is derived from the tuning per shape and
/// shown to the player rather than assumed. In a non-standard tuning it is
/// whatever that tuning makes it.
@MainActor
@Observable
final class OctavesModuleModel {
    private(set) var rootPitchClass = PitchClass(0)
    /// `"string:fret"` of the anchored root.
    private(set) var anchorKey = "0:8"
    private(set) var pulses: [String: Double] = [:]

    /// The recall round. Transient by design — never persisted.
    let challenge = RecallChallenge<OctaveShape, String>()

    var tuning: Tuning
    let highestFret = LearningModule.octaves.highestFret

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
        let saved = store?.state.modules.octaves ?? PracticeState.Modules.Octaves()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        anchorKey = saved.anchor
    }

    // MARK: - Shapes

    var shapes: [OctaveShape] {
        OctaveShapes.shapes(root: rootPitchClass, tuning: tuning, fretCount: highestFret)
    }

    static func key(_ position: NeckPosition) -> String { "\(position.string):\(position.fret)" }

    private var preferredPosition: NeckPosition {
        let parts = anchorKey.split(separator: ":")
        let string = parts.count == 2 ? Int(parts[0]) ?? 0 : 0
        let fret = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        return NeckPosition(string: string, fret: fret, midiNote: 0, pitchClass: rootPitchClass)
    }

    var anchoredShape: OctaveShape? {
        OctaveShapes.resolve(shapes: shapes, preferred: preferredPosition)
    }

    /// While a round is running the board follows the *prompt*, not the
    /// anchor — otherwise answering would move the question.
    var currentShape: OctaveShape? {
        challenge.prompt?.context ?? anchoredShape
    }

    var anchoredIndex: Int? {
        guard let shape = anchoredShape else { return nil }
        return shapes.firstIndex { Self.key($0.root) == Self.key(shape.root) }
    }

    /// The offset for the shape in play, in frets. Two in most of standard
    /// tuning, three across the G–B pair.
    var fretOffset: Int? { currentShape?.fretOffset }

    // MARK: - Dots

    var dots: [FretboardDot] {
        guard let shape = currentShape else { return [] }
        let hideTarget = challenge.isAcceptingAnswers
        var dots: [FretboardDot] = []

        // The other roots, recessed: where else this shape could sit.
        for other in shapes where Self.key(other.root) != Self.key(shape.root) {
            dots.append(FretboardDot(
                id: "octave-root-option-\(Self.key(other.root))",
                position: FretPosition(string: other.root.string, fret: other.root.fret),
                label: rootPitchClass.name(),
                color: NotePalette.color(for: other.root.pitchClass),
                radius: 9,
                alpha: 0.42
            ))
        }

        dots.append(FretboardDot(
            id: "octave-root-\(Self.key(shape.root))",
            position: FretPosition(string: shape.root.string, fret: shape.root.fret),
            label: rootPitchClass.name(),
            color: NotePalette.color(for: .root),
            outline: true
        ))

        // Hidden while the player is being asked to find it — showing the
        // answer during the question is the one thing a recall round must not
        // do.
        if !hideTarget {
            dots.append(FretboardDot(
                id: "octave-target-\(Self.key(shape.target))",
                position: FretPosition(string: shape.target.string, fret: shape.target.fret),
                label: rootPitchClass.name(),
                color: NotePalette.color(for: .fifth),
                ring: .white,
                outline: true
            ))
        }

        // A wrong answer stays visible so the player can see what they picked
        // against where it should have been.
        if challenge.phase == .incorrect, let answer = challenge.lastAnswer,
           let position = Self.position(fromKey: answer, tuning: tuning, highestFret: highestFret) {
            dots.append(FretboardDot(
                id: "octave-attempt-\(answer)",
                position: position,
                label: "?",
                color: NotePalette.color(for: .outsideShape),
                outline: true
            ))
        }
        return dots
    }

    static func position(fromKey key: String, tuning: Tuning, highestFret: Int) -> FretPosition? {
        let parts = key.split(separator: ":")
        guard parts.count == 2,
              let string = Int(parts[0]),
              let fret = Int(parts[1]),
              tuning.openMIDINotes.indices.contains(string),
              (0...highestFret).contains(fret)
        else { return nil }
        return FretPosition(string: string, fret: fret)
    }

    // MARK: - Selection

    func selectRoot(_ pitchClass: PitchClass) {
        challenge.stop()
        stop()
        rootPitchClass = pitchClass
        reanchor()
        persist()
    }

    /// Tapping another root moves the shape there. Ignored mid-round, where a
    /// tap means an answer instead.
    func selectAnchor(string: Int, fret: Int) {
        guard !challenge.isAcceptingAnswers else { return }
        let candidate = NeckPosition(string: string, fret: fret, midiNote: 0, pitchClass: rootPitchClass)
        guard let resolved = OctaveShapes.resolve(shapes: shapes, preferred: candidate) else { return }
        stop()
        anchorKey = Self.key(resolved.root)
        persist()
        // A tap on the fretboard itself should always be heard — the root
        // menu above deliberately stays silent, but this is the direct
        // "touch the instrument" gesture.
        let root = FretPosition(string: resolved.root.string, fret: resolved.root.fret)
        play(root)
        pulse("octave-root-\(Self.key(resolved.root))")
    }

    /// Step to the next or previous shape along the neck, wrapping. The web
    /// binds this to the arrow keys.
    func moveAnchor(by delta: Int) {
        guard !challenge.isRunning, !shapes.isEmpty, let index = anchoredIndex else { return }
        let next = ((index + delta) % shapes.count + shapes.count) % shapes.count
        stop()
        anchorKey = Self.key(shapes[next].root)
        persist()
    }

    func retune(to tuning: Tuning) {
        challenge.stop()
        stop()
        self.tuning = tuning
        reanchor()
        persist()
    }

    private func reanchor() {
        guard let shape = anchoredShape else { return }
        anchorKey = Self.key(shape.root)
    }

    private func persist() {
        let root = rootPitchClass.value
        let anchor = anchorKey
        store?.update {
            $0.modules.octaves.rootPitchClass = root
            $0.modules.octaves.anchor = anchor
        }
    }

    // MARK: - The recall round

    /// Deals every shape for this root, starting from wherever the player is
    /// anchored, so the round begins with the shape already in front of them.
    func startRecall() {
        stop()
        let ordered = shapes
        guard !ordered.isEmpty else { return }
        let start = anchoredIndex ?? 0
        let deck = Array(ordered[start...] + ordered[..<start])
        challenge.start(deck.map { shape in
            RecallChallenge.Prompt(
                id: "octave-\(Self.key(shape.root))",
                context: shape,
                expected: Self.key(shape.target)
            )
        })
    }

    /// A tap during a round is an answer. Right, and the octave sounds; wrong,
    /// and the note actually picked sounds — hearing that it is not an octave
    /// is the correction.
    func answerCell(string: Int, fret: Int) {
        guard challenge.isAcceptingAnswers, let shape = currentShape else { return }
        let answer = "\(string):\(fret)"
        challenge.answer(answer)

        if challenge.phase == .correct {
            playShape(shape, gap: 0.45)
        } else if let position = Self.position(fromKey: answer, tuning: tuning, highestFret: highestFret) {
            play(position)
            pulse("octave-attempt-\(answer)")
        }
    }

    func stopRecall() {
        challenge.stop()
        stop()
    }

    // MARK: - Playback

    /// Root then octave, so the distance is heard rather than only seen.
    func hearOctave() {
        guard let shape = currentShape else { return }
        playShape(shape, gap: 0.6)
    }

    private func playShape(_ shape: OctaveShape, gap: TimeInterval) {
        let rootPosition = FretPosition(string: shape.root.string, fret: shape.root.fret)
        let targetPosition = FretPosition(string: shape.target.string, fret: shape.target.fret)

        let sequencer = sequencer ?? NoteSequencer { [weak self] position, _, _ in
            Task { @MainActor [weak self] in self?.play(position) }
        }
        self.sequencer = sequencer

        var options = NoteSequencer.Options()
        options.gap = gap
        options.onHit = { [weak self] position, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pulse(position == rootPosition
                    ? "octave-root-\(Self.key(shape.root))"
                    : "octave-target-\(Self.key(shape.target))")
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
