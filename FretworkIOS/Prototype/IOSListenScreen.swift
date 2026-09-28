import Foundation
import SwiftUI

/// The iOS Listen screen.
///
/// Portrait is a pure tuner (D-16): no fretboard — just the note/chord
/// readout, cents·Hz, input level, history and a quiet rotate hint. Landscape
/// reveals the full 22-fret neck with a compact tuner strip above it (D-17,
/// D-22).
///
/// **Audio-rate reads live only in the small leaf views below.** The parent
/// body reads `detectionMode` (changes on tap), orientation and the
/// event-driven iOS status only — never `display`, `chordDisplay` or the
/// history arrays (D-08).
struct IOSListenScreen: View {
    @Bindable var state: AppState

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if isLandscape {
                landscape
            } else {
                portrait
            }
        }
        .background(NotePalette.backdrop)
        .task {
            // Start listening once, on first appear. A later re-appear (after
            // browsing a module) must not restart the engine — that would
            // re-prompt for the mic and re-negotiate the route. The controller
            // status tells us whether it is already running.
            switch state.iosAudio?.status {
            case .idle, nil:
                state.start()
            default:
                break
            }
        }
    }

    // MARK: - Portrait

    private var portrait: some View {
        VStack(spacing: 12) {
            headerRow
            statusBanner
            Spacer(minLength: 0)
            readout
            Spacer(minLength: 0)
            inputLevel
            history
            rotateHint
        }
        .padding(16)
    }

    // MARK: - Landscape

    private var landscape: some View {
        VStack(spacing: 10) {
            headerRow
            statusBanner
            IOSLandscapeTunerStrip(state: state, mode: state.detectionMode)
            IOSBoardLeaf(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var headerRow: some View {
        HStack {
            IOSStatusPill(state: state)
            Spacer()
            Picker("Detection mode", selection: $state.detectionMode) {
                ForEach(DetectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
    }

    @ViewBuilder
    private var readout: some View {
        switch state.detectionMode {
        case .notes:
            IOSNotesTunerReadout(state: state)
        case .chords:
            IOSChordsTunerReadout(state: state)
        }
    }

    private var inputLevel: some View {
        IOSInputLevelLeaf(state: state, mode: state.detectionMode)
    }

    private var history: some View {
        IOSHistoryLeaf(state: state, mode: state.detectionMode)
    }

    private var rotateHint: some View {
        HStack(spacing: 9) {
            Image(systemName: "rotate.right")
            Text("Turn your phone to see it on the neck")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if state.iosAudio?.status == .permissionDenied {
            HStack(spacing: 10) {
                Image(systemName: "mic.slash.fill").foregroundStyle(.red)
                Text("Microphone access is off.")
                    .font(.callout)
                Spacer()
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Leaves (one per audio-rate read)

/// The event-driven listening status, as a small pill. Reads the iOS
/// controller's status — not the audio-rate `display`.
private struct IOSStatusPill: View {
    let state: AppState

    var body: some View {
        let (text, tint) = Self.status(for: state.iosAudio?.status)
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.9), radius: 4)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: text)
    }

    private static func status(for status: IOSAudioStatus?) -> (String, Color) {
        switch status {
        case .listening: ("Listening", .green)
        case .starting: ("Starting…", .orange)
        case .interrupted: ("Paused", .orange)
        case .permissionDenied: ("Mic off", .red)
        case .failed: ("Audio error", .red)
        case .idle, nil: ("Stopped", .secondary)
        }
    }
}

/// Portrait Notes readout: the big tinted note capsule, the cents gauge and
/// the cents·Hz line. Owns the `display` read.
private struct IOSNotesTunerReadout: View {
    let state: AppState

    var body: some View {
        let display = state.display
        let note = display.note
        let color = note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14)

        VStack(spacing: 14) {
            Text("NOTE")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note?.name ?? "—")
                    .font(.system(size: 110, weight: .black))
                    .tracking(-3)
                if let note {
                    Text("\(note.octave)")
                        .font(.system(size: 40, weight: .bold))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 44)
            .frame(height: 150)
            .background(Capsule().fill(color.opacity(0.25)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: note?.midiNote)

            TunerGauge(displayCents: note?.cents ?? 0, isActive: note != nil)
                .frame(height: 54)

            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(note.map { String(format: "%+.0f", $0.cents) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("CENTS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(display.frequency.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("HZ")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Portrait Chords readout: the big chord capsule and the confidence bar.
/// Owns the `chordDisplay` read.
private struct IOSChordsTunerReadout: View {
    let state: AppState

    var body: some View {
        let chord = state.chordDisplay.chord
        let color = chord.map { NotePalette.color(for: $0.root) } ?? Color.white.opacity(0.14)

        VStack(spacing: 14) {
            Text("CHORD")
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(chord?.name ?? "—")
                .font(.system(size: 96, weight: .black))
                .tracking(-2)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, 38)
                .frame(height: 150)
                .background(Capsule().fill(color.opacity(0.25)))
                .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: chord?.name)

            VStack(spacing: 10) {
                HStack {
                    Text("CONFIDENCE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(chord.map { "\(Int(($0.confidence * 100).rounded()))%" } ?? "—")
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * CGFloat(chord?.confidence ?? 0))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

/// The compact horizontal tuner used in landscape. Still one leaf: it owns the
/// `display` / `chordDisplay` reads it draws.
private struct IOSLandscapeTunerStrip: View {
    let state: AppState
    let mode: DetectionMode

    var body: some View {
        Group {
            switch mode {
            case .notes: notesStrip
            case .chords: chordsStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var notesStrip: some View {
        let display = state.display
        let note = display.note
        let color = note.map { NotePalette.color(for: $0.name) } ?? Color.white.opacity(0.14)

        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(note?.name ?? "—")
                    .font(.system(size: 40, weight: .black))
                    .tracking(-2)
                if let note {
                    Text("\(note.octave)")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(color.opacity(0.25)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .animation(.easeInOut(duration: 0.2), value: note?.midiNote)

            TunerGauge(displayCents: note?.cents ?? 0, isActive: note != nil)
                .frame(height: 44)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(note.map { String(format: "%+.0f", $0.cents) } ?? "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("CENTS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(display.frequency.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("HZ")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                IOSCompactLevelMeter(level: display.level)
            }
            .frame(width: 210)
        }
    }

    @ViewBuilder
    private var chordsStrip: some View {
        let chord = state.chordDisplay.chord
        let color = chord.map { NotePalette.color(for: $0.root) } ?? Color.white.opacity(0.14)

        HStack(spacing: 14) {
            Text(chord?.name ?? "—")
                .font(.system(size: 36, weight: .black))
                .tracking(-2)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(color.opacity(0.25)))
                .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
                .animation(.easeInOut(duration: 0.2), value: chord?.name)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("CONFIDENCE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(chord.map { "\(Int(($0.confidence * 100).rounded()))%" } ?? "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * CGFloat(chord?.confidence ?? 0))
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                Text("INPUT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                IOSCompactLevelMeter(level: state.chordDisplay.level)
            }
            .frame(width: 160)
        }
    }
}

/// A tiny segmented level bar for the landscape strip (the full
/// `InputLevelPanel` card is portrait-only).
private struct IOSCompactLevelMeter: View {
    let level: Float

    var body: some View {
        let normalized = InputLevelPanel.normalized(level)
        GeometryReader { proxy in
            let columns = max(2, Int(proxy.size.width / 9))
            HStack(spacing: 2) {
                ForEach(0..<columns, id: \.self) { column in
                    let fraction = Double(column) / Double(columns - 1)
                    let lit = column < Int((normalized * Double(columns)).rounded())
                    RoundedRectangle(cornerRadius: 1)
                        .fill(lit
                              ? (fraction < 0.69 ? Color.green : (fraction < 0.885 ? Color.yellow : Color.red))
                              : Color.white.opacity(0.10))
                }
            }
        }
        .frame(height: 4)
    }
}

/// Owns the level read, which lives in `display` in Notes mode and
/// `chordDisplay` in Chords mode.
private struct IOSInputLevelLeaf: View {
    let state: AppState
    let mode: DetectionMode

    var body: some View {
        switch mode {
        case .notes:
            InputLevelPanel(level: state.display.level)
        case .chords:
            InputLevelPanel(level: state.chordDisplay.level)
        }
    }
}

/// Owns the history read (notes or chords).
private struct IOSHistoryLeaf: View {
    let state: AppState
    let mode: DetectionMode

    var body: some View {
        switch mode {
        case .notes:
            HistoryStrip(
                history: state.noteHistory,
                pinnedID: state.pinnedNoteHistoryID,
                label: { "\($0.note.name)\($0.note.octave)" },
                tint: { NotePalette.color(for: $0.note.name) },
                noun: "note",
                onSelect: { state.pinnedNoteHistoryID = $0 },
                onClear: { state.clearNoteHistory() }
            )
        case .chords:
            HistoryStrip(
                history: state.chordHistory,
                pinnedID: state.pinnedChordHistoryID,
                label: { $0.match.name },
                tint: { NotePalette.color(for: $0.match.root) },
                noun: "chord",
                onSelect: { state.pinnedChordHistoryID = $0 },
                onClear: { state.clearChordHistory() }
            )
        }
    }
}

/// The landscape neck: the existing listening board + `DetectionBoardAdapter`,
/// fitted to whatever width remains.
private struct IOSBoardLeaf: View {
    let state: AppState

    var body: some View {
        FretboardView(
            mode: state.detectionMode,
            note: state.displayedNote,
            positions: state.displayedPositions,
            chord: state.displayedChord,
            flipped: state.isFretboardFlipped
        )
    }
}
