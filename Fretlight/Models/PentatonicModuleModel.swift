import Foundation
import SwiftUI

/// Pentatonic scales — five boxes, and guided practice through one of them.
///
/// Ported from `../fretwork/src/lib/modules/Pentatonic.svelte`.
///
/// The five positions are two-notes-per-string boxes covering the whole neck
/// between them, and the module can show one, a pair, or a three-box path. In
/// the multi-box views the neighbours are drawn recessed and unlabelled: they
/// are there to show how the boxes join, and a fully-labelled neck is a wall of
/// dots rather than a shape.
///
/// **Standard tuning only, and not parameterised by one.** `ScaleShapes`
/// records why: these boxes are fixed fret offsets from a computed base, so a
/// different tuning does not transpose them — it detunes them, and the box
/// quietly stops being the scale it claims to be. `CLAUDE.md` notes this
/// slipped in twice before.
@MainActor
@Observable
final class PentatonicModuleModel {
    enum DisplayMode: String, Sendable, CaseIterable {
        case single, pair, path
    }

    private(set) var rootPitchClass = PitchClass(9)
    private(set) var quality: PentatonicQuality = .minorPentatonic
    /// 0...4, matching `ScaleShapes.pentatonicPosition`, which indexes its
    /// pattern table directly. Displayed as "Box 1"–"Box 5"; a 1-based store
    /// would silently return an empty box for 5 and shift every other one.
    private(set) var position = 0
    private(set) var displayMode: DisplayMode = .single
    private(set) var displayStart = 0
    private(set) var pulses: [String: Double] = [:]
    private(set) var guidedSnapshot = GuidedSession<GuidedScaleStep>.Snapshot()
    private(set) var currentStep: GuidedScaleStep?

    let highestFret = LearningModule.pentatonic.highestFret

    private let store: PracticeStateStore?
    private let play: (FretPosition) -> Void
    private var guided: GuidedSession<GuidedScaleStep>?

    init(
        store: PracticeStateStore? = nil,
        play: @escaping (FretPosition) -> Void = { _ in }
    ) {
        self.store = store
        self.play = play
        let saved = store?.state.modules.pentatonic ?? PracticeState.Modules.Pentatonic()
        rootPitchClass = PitchClass(saved.rootPitchClass)
        quality = PentatonicQuality(rawValue: saved.quality) ?? .minorPentatonic
        position = saved.position
        displayMode = DisplayMode(rawValue: saved.displayMode) ?? .single
        displayStart = saved.displayStart
    }

    // MARK: - Boxes

    /// Which boxes are on screen. A pair is this box and the next; a path is
    /// three, with the focus in the middle so you can see where it came from
    /// and where it goes.
    var visiblePositions: [Int] {
        switch displayMode {
        case .single: [position]
        case .pair: [displayStart, displayStart + 1].filter { (0...4).contains($0) }
        case .path: [displayStart, displayStart + 1, displayStart + 2].filter { (0...4).contains($0) }
        }
    }

    /// The box being practised. In `path` the middle one is the subject.
    var focusPosition: Int {
        displayMode == .path ? min(max(displayStart + 1, 0), 4) : (visiblePositions.first ?? position)
    }

    var box: [GuidedScaleStep] {
        ScaleShapes.pentatonicPosition(root: rootPitchClass, quality: quality, position: focusPosition)
    }

    private var contextBoxes: [(position: Int, steps: [GuidedScaleStep])] {
        visiblePositions.filter { $0 != focusPosition }.map {
            ($0, ScaleShapes.pentatonicPosition(root: rootPitchClass, quality: quality, position: $0))
        }
    }

    // MARK: - Dots

    /// Focus box full size and labelled; neighbours recessed and unlabelled.
    var dots: [FretboardDot] {
        var dots: [FretboardDot] = []

        for context in contextBoxes {
            for step in context.steps {
                dots.append(FretboardDot(
                    id: "pent-context-\(context.position)-\(step.string)-\(step.fret)",
                    position: FretPosition(string: step.string, fret: step.fret),
                    label: "",
                    color: NotePalette.color(for: .outsideShape),
                    radius: 8,
                    alpha: 0.35
                ))
            }
        }

        for step in box {
            let isRoot = step.pitchClass == rootPitchClass
            let isCurrent = currentStep.map { $0.id == step.id } ?? false
            dots.append(FretboardDot(
                id: step.id,
                position: FretPosition(string: step.string, fret: step.fret),
                label: step.degree,
                color: NotePalette.color(for: isRoot ? .root : .pentatonic),
                ring: isCurrent ? .white : (isRoot ? .white : nil),
                ringAlpha: isCurrent ? 1 : 0.5,
                outline: true
            ))
        }
        return dots
    }

    // MARK: - Selection

    func selectRoot(_ pitchClass: PitchClass) {
        stop()
        rootPitchClass = pitchClass
        persist()
    }

    func selectQuality(_ quality: PentatonicQuality) {
        stop()
        self.quality = quality
        persist()
    }

    /// - Parameter position: 0...4.
    func selectPosition(_ position: Int) {
        guard (0...4).contains(position) else { return }
        stop()
        self.position = position
        displayStart = clampedStart(for: displayMode, focus: position)
        persist()
    }

    func selectDisplayMode(_ mode: DisplayMode) {
        stop()
        displayMode = mode
        displayStart = clampedStart(for: mode, focus: position)
        persist()
    }

    /// A pair or path has to fit inside 1...5, so the start is clamped rather
    /// than allowed to run off the end and silently show fewer boxes.
    private func clampedStart(for mode: DisplayMode, focus: Int) -> Int {
        switch mode {
        case .single: focus
        case .pair: min(max(focus, 0), 3)
        case .path: min(max(focus - 1, 0), 2)
        }
    }

    private func persist() {
        let snapshot = (root: rootPitchClass.value, quality: quality.rawValue,
                        position: position, mode: displayMode.rawValue, start: displayStart)
        store?.update {
            $0.modules.pentatonic.rootPitchClass = snapshot.root
            $0.modules.pentatonic.quality = snapshot.quality
            $0.modules.pentatonic.position = snapshot.position
            $0.modules.pentatonic.displayMode = snapshot.mode
            $0.modules.pentatonic.displayStart = snapshot.start
        }
    }

    // MARK: - Guided practice

    /// Ascends the box one note per beat after a four-beat count-in, lighting
    /// and sounding each note as it comes.
    func startGuided() {
        let steps = box
        guard !steps.isEmpty else { return }
        stop()

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
        session.start(steps)
        guidedSnapshot = session.snapshot
    }

    func stopGuided() {
        guided?.stop()
        guidedSnapshot = GuidedSession<GuidedScaleStep>.Snapshot()
        currentStep = nil
    }

    @discardableResult func slower() -> Int { guided?.slower() ?? GuidedSession<GuidedScaleStep>.defaultTempoBpm }
    @discardableResult func faster() -> Int { guided?.faster() ?? GuidedSession<GuidedScaleStep>.defaultTempoBpm }

    /// The note after the current one, so the player can see where the hand is
    /// going rather than only where it is.
    var nextStep: GuidedScaleStep? {
        guard let index = guidedSnapshot.currentIndex else { return nil }
        let steps = box
        return steps.indices.contains(index + 1) ? steps[index + 1] : nil
    }

    func stop() {
        stopGuided()
        pulses.removeAll()
    }
}
