#if DEBUG
import Observation
import SwiftUI

/// The input level, on its own object rather than on `SampleCaptureModel`.
///
/// This updates at audio rate while the 138-cell grid does not. `@Observable`
/// tracks reads per view body, so putting the level on the model would make
/// every level update invalidate every view that reads anything else about the
/// session — the grid included. Keeping it separate confines those updates to
/// the one leaf view that draws the meter.
@MainActor @Observable
final class CaptureLevelMeter {
    private(set) var level: Float = 0

    /// Compare before assigning: storing an equal value still fires
    /// `withMutation` and invalidates observers.
    func update(_ value: Float) {
        guard abs(value - level) > 0.001 else { return }
        level = value
    }
}

/// Whether the recorder is waiting for a note. Separate from the level meter
/// on purpose: the level changes at audio rate and this does not, so sharing
/// one object would drag the arm button into every level update.
@MainActor @Observable
final class CaptureArmState {
    var isArmed = false
}

struct SampleCaptureView: View {
    /// Measured, not guessed — see `SampleCaptureViewTests`, which renders this
    /// view off-screen and fails if the declared size cannot contain it.
    static let minimumSize = CGSize(width: 760, height: 560)

    let model: SampleCaptureModel
    let meter: CaptureLevelMeter
    let arm: CaptureArmState
    let onArm: () -> Void
    let onDisarm: () -> Void
    let onChooseDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LevelSection(meter: meter)
            VerdictSection(model: model)
            NeckGrid(model: model)
            controls
            issues
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.035, green: 0.045, blue: 0.047))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            PromptSection(model: model)
            Spacer(minLength: 8)
            ProgressSection(model: model)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ArmButton(arm: arm, isEnabled: model.currentPosition != nil, onArm: onArm, onDisarm: onDisarm)

            Button("Skip") { skip() }
                .disabled(model.currentPosition == nil)

            Button("Retake") { model.retakeCurrent() }
                .disabled(model.currentPosition == nil)

            Divider().frame(height: 18)

            Button("Choose folder…", action: onChooseDirectory)
            Button("Refresh") { model.refresh() }
            Spacer(minLength: 0)
        }
    }

    private func skip() {
        guard let current = model.currentPosition,
              let index = SampleLibrary.expectedPositions.firstIndex(of: current),
              index + 1 < SampleLibrary.expectedPositions.count
        else { return }
        model.jump(to: SampleLibrary.expectedPositions[index + 1])
    }

    @ViewBuilder
    private var issues: some View {
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
        if !model.reconciliationIssues.isEmpty {
            Text("\(model.reconciliationIssues.count) library issue(s) — the manifest and the folder disagree")
                .font(.callout)
                .foregroundStyle(.yellow)
        }
    }
}

// MARK: - Leaf views
//
// Each reads one slice of state. The split is the same one `ContentView` uses
// and exists for the same reason: `@Observable` invalidates per view body, so
// a read in the parent would rebuild everything below it.

private struct ArmButton: View {
    let arm: CaptureArmState
    let isEnabled: Bool
    let onArm: () -> Void
    let onDisarm: () -> Void

    var body: some View {
        Button(arm.isArmed ? "Waiting for note…" : "Arm") {
            arm.isArmed ? onDisarm() : onArm()
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!isEnabled)
    }
}

private struct PromptSection: View {
    let model: SampleCaptureModel

    var body: some View {
        if let position = model.currentPosition {
            let midi = Tunings.standard.openMIDINotes[position.string] + position.fret
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Tunings.standard.stringNames[position.string]) string, fret \(position.fret)")
                    .font(.title2.weight(.semibold))
                Text("\(PitchClass(midi).name())\(midi / 12 - 1) · MIDI \(midi)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("All 138 positions recorded")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
        }
    }
}

private struct ProgressSection: View {
    let model: SampleCaptureModel

    var body: some View {
        Text("\(model.recordedCount) of \(SampleLibrary.expectedPositions.count) · \(model.remainingCount) to go")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

private struct LevelSection: View {
    let meter: CaptureLevelMeter

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.8))
                    .frame(width: proxy.size.width * CGFloat(min(meter.level * 4, 1)))
                // Where a note starts counting, so the operator can see that a
                // light stroke will actually trigger before they play 138 of them.
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 1)
                    .offset(x: proxy.size.width * CGFloat(min(TakeVerifier.minimumPeak * 4, 1)))
            }
        }
        .frame(height: 14)
    }
}

private struct VerdictSection: View {
    let model: SampleCaptureModel

    var body: some View {
        switch model.lastVerdict {
        case nil:
            Text("Play the prompted note.").font(.callout).foregroundStyle(.secondary)
        case let .accepted(frequency, cents):
            Label(String(format: "Accepted · %.1f Hz · %+.1f cents", frequency, cents), systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        case let .wrongPitch(cents):
            Label(String(format: "Wrong pitch · %+.1f cents — check the fret and the tuning", cents), systemImage: "xmark.circle.fill")
                .font(.callout).foregroundStyle(.red)
        case .noStablePitch:
            Label("No stable pitch — a dead or buzzed note", systemImage: "waveform.badge.exclamationmark")
                .font(.callout).foregroundStyle(.orange)
        case .tooQuiet:
            Label("Too quiet to judge — play harder or raise the input gain", systemImage: "speaker.slash.fill")
                .font(.callout).foregroundStyle(.orange)
        }
    }
}

private struct NeckGrid: View {
    let model: SampleCaptureModel

    var body: some View {
        VStack(spacing: 3) {
            // Highest string at the top, matching the board elsewhere in the app.
            ForEach(Array((0..<SampleLibrary.stringCount).reversed()), id: \.self) { string in
                HStack(spacing: 3) {
                    ForEach(0...SampleLibrary.highestFret, id: \.self) { fret in
                        let position = FretPosition(string: string, fret: fret)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: position))
                            .overlay {
                                if model.currentPosition == position {
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.5)
                                }
                            }
                            .frame(height: 18)
                            .onTapGesture { model.jump(to: position) }
                    }
                }
            }
        }
    }

    private func color(for position: FretPosition) -> Color {
        switch model.statuses[position] ?? .missing {
        case .missing: Color.white.opacity(0.07)
        case .recorded: Color.green.opacity(0.55)
        case .flagged: Color.yellow.opacity(0.6)
        }
    }
}
#endif
