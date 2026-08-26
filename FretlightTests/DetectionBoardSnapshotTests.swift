import AppKit
import SwiftUI
import XCTest
@testable import Fretwork

/// Renders the detection board to PNGs so a refactor can be checked against
/// pixels rather than against a diff.
///
/// Writes into a directory named by `FRETWORK_SNAPSHOT_DIR`; skips entirely
/// when that is unset, so it costs nothing on an ordinary run.
@MainActor
final class DetectionBoardSnapshotTests: XCTestCase {
    private func note(_ midi: Int) -> MappedNote {
        let mapped = NoteMapper.map(frequency: 440 * pow(2, Double(midi - 69) / 12))!
        return mapped
    }

    private func cases() -> [(String, FretboardView)] {
        let a2 = note(45)
        let positions = GuitarTuning.positions(forMIDI: 45).enumerated().map {
            RankedPosition(position: $1, rank: $0)
        }
        let chord = ChordMatch(root: "E", quality: .major, confidence: 0.9)
        return [
            ("notes", FretboardView(mode: .notes, note: a2, positions: positions, chord: nil, flipped: false)),
            ("notes-flipped", FretboardView(mode: .notes, note: a2, positions: positions, chord: nil, flipped: true)),
            ("notes-empty", FretboardView(mode: .notes, note: nil, positions: [], chord: nil, flipped: false)),
            ("chords", FretboardView(mode: .chords, note: nil, positions: [], chord: chord, flipped: false)),
            ("chords-empty", FretboardView(mode: .chords, note: nil, positions: [], chord: nil, flipped: false))
        ]
    }

    func testCaptureDetectionBoardSnapshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["FRETWORK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set FRETWORK_SNAPSHOT_DIR to capture")
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for (name, view) in cases() {
            let host = NSHostingView(rootView: view.frame(width: 900, height: 280))
            host.frame = CGRect(x: 0, y: 0, width: 900, height: 280)
            host.layout()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
    }
}
