#if DEBUG
import Foundation
import Observation

enum SampleCapturePositionStatus: Sendable {
    case missing
    case recorded
    /// Recorded, but its level sits well off the session median — worth a
    /// second listen before the library is built.
    case flagged
}

/// Where the operator keeps the masters. Its own defaults key rather than a
/// field in `PracticeState`: that document is shipped schema, and a
/// maintainer-only path has no business in it.
///
/// A plain path rather than a security-scoped bookmark, because this app is
/// not sandboxed (`ENABLE_APP_SANDBOX = NO`). If that ever changes, this is
/// the thing that breaks — a resumed session would silently find nothing and
/// offer to start the 138 takes again.
enum SampleCaptureDirectory {
    private static let key = "fretwork.debug.sample-capture-directory"

    /// Takes its store rather than reaching for `.standard`, so a test can
    /// prove resume works without writing into the real defaults domain.
    static func url(in defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setURL(_ url: URL?, in defaults: UserDefaults = .standard) {
        defaults.set(url?.path, forKey: key)
    }
}

/// The whole sample-capture session: what to record next, what the last take
/// was judged to be, and what the library still needs.
///
/// All of it lives here rather than in the view so it can be driven by tests
/// with synthesised takes — the session logic is the part worth getting right,
/// and a 138-take recording session is not something to debug by hand.
@MainActor @Observable
final class SampleCaptureModel {
    private let library: SampleLibrary
    /// Shown in the capture window. Resuming into the wrong folder looks
    /// exactly like having recorded nothing, so the folder has to be visible
    /// rather than merely remembered.
    let directory: URL

    private(set) var currentPosition: FretPosition?
    private(set) var lastVerdict: TakeVerdict?
    /// The numbers behind `lastVerdict`, so a rejection can be diagnosed from
    /// the capture window rather than from a rebuild.
    private(set) var lastDiagnostics: String?
    private(set) var statuses: [FretPosition: SampleCapturePositionStatus] = [:]
    private(set) var recordedCount = 0
    /// Disagreements between the manifest and the directory. Surfaced, never
    /// repaired: a missing sample is a prompt to re-record that position.
    private(set) var reconciliationIssues: [SampleLibraryIssue] = []
    /// A write or read that failed outright. Deliberately separate from
    /// `reconciliationIssues` — a library that could not be written is a
    /// different problem from one that disagrees with itself, and folding the
    /// two together would report an I/O error as a stray audio file.
    private(set) var lastError: String?

    var remainingCount: Int { SampleLibrary.expectedPositions.count - recordedCount }

    init(directory: URL) {
        self.directory = directory
        library = SampleLibrary(directory: directory)
        refresh()
        currentPosition = firstMissing()
    }

    func jump(to position: FretPosition) {
        guard SampleLibrary.expectedPositions.contains(position) else { return }
        currentPosition = position
        lastVerdict = nil
    }

    /// Clears the previous judgement so the next take is read on its own terms.
    /// The position itself does not move — `write` replaces an existing entry.
    func retakeCurrent() {
        lastVerdict = nil
    }

    func handle(take: SampleRecorder.Take) {
        guard let position = currentPosition else { return }
        let verdict = TakeVerifier.verify(take, string: position.string, fret: position.fret)
        lastVerdict = verdict
        lastDiagnostics = TakeVerifier.diagnostics(take, string: position.string, fret: position.fret)
        guard case let .accepted(frequency, cents) = verdict else { return }

        let prepared = TakeVerifier.normalized(TakeVerifier.trimmed(take))
        do {
            try library.write(
                take: prepared,
                string: position.string,
                fret: position.fret,
                frequency: frequency,
                cents: cents,
                // The take before normalisation — that is the level the player
                // actually struck, and the only one worth comparing across a
                // long session.
                rawPeak: take.peak
            )
            lastError = nil
            refresh()
            advance(past: position)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() {
        do {
            let entries = try library.entries()
            recordedCount = entries.count
            var next = Dictionary(
                uniqueKeysWithValues: SampleLibrary.expectedPositions.map { ($0, SampleCapturePositionStatus.missing) }
            )
            for entry in entries {
                next[FretPosition(string: entry.string, fret: entry.fret)] = entry.peakFlagged ? .flagged : .recorded
            }
            statuses = next
            reconciliationIssues = try library.reconcile()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Continues from where the operator actually is rather than snapping back
    /// to the first gap on the neck: someone filling in a position they missed
    /// mid-session should carry on from there, not be thrown to the nut.
    private func advance(past position: FretPosition) {
        let missing = Set(missingPositions())
        guard !missing.isEmpty else {
            currentPosition = nil
            return
        }
        let ordered = SampleLibrary.expectedPositions
        guard let index = ordered.firstIndex(of: position) else {
            currentPosition = firstMissing()
            return
        }
        currentPosition = ordered[(index + 1)...].first { missing.contains($0) } ?? firstMissing()
    }

    private func missingPositions() -> [FretPosition] {
        SampleLibrary.expectedPositions.filter { statuses[$0] == .missing }
    }

    private func firstMissing() -> FretPosition? {
        missingPositions().first
    }
}
#endif
