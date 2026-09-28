import XCTest
import Foundation
@testable import Fretwork

/// The iOS app must ship the recorded note library.
///
/// Phase 2's per-target exception set held the 139 `Resources/NoteSamples/…`
/// files out of the iOS bundle; the owner decided (2026-09-28) that the ~13 MB
/// is acceptable and the lessons need the samples. Removing those exceptions
/// *includes* the resources, and because `Fretlight/` is a synchronized root
/// they land flat in `Contents/Resources`, which is exactly what
/// `NoteSampleLibrary.loadFromBundle()` looks up. These tests keep the library
/// from silently dropping back out of the bundle.
final class IOSNoteSampleBundleTests: XCTestCase {
    /// Presence: fast, no decode. The presence guard that runs on every build.
    func testBundleContainsAll138SamplesAndIndex() {
        let m4a = Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: nil) ?? []
        XCTAssertEqual(m4a.count, 138, "iOS bundle must ship all 138 note samples")
        XCTAssertNotNil(Bundle.main.url(forResource: "index", withExtension: "json"))
    }

    /// Index loads: decode the manifest JSON without decoding 85 MB of audio.
    func testIndexLoadsAndLists138Positions() throws {
        struct Row: Decodable {
            let string: Int
            let fret: Int
            let targetMIDI: Int
            let filename: String
        }
        struct Index: Decodable { let positions: [Row] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "json"))
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
        XCTAssertEqual(index.positions.count, 138)
        XCTAssertEqual(Set(index.positions.map(\.filename)).count, 138)
        // A tuple is not Hashable; key the pair so the uniqueness check still runs.
        XCTAssertEqual(Set(index.positions.map { "\($0.string)-\($0.fret)" }).count, 138)
    }

    /// Full decode + lookup: the real guarantee, at the cost of seconds and
    /// ~85 MB. Bundle-only (no hardware, no `AVAudioSession`), so it still
    /// satisfies C-11; it is the slow acceptance gate that would catch a decode
    /// regression rather than a dropped file.
    func testLibraryDecodesAndResolvesNeckCorners() throws {
        let library = try NoteSampleLibrary.loadFromBundle(.main)
        XCTAssertEqual(library.count, 138)
        XCTAssertNotNil(library.sample(string: 0, fret: 0))   // low E open
        XCTAssertNotNil(library.sample(string: 5, fret: 22))  // high e, 22nd fret
    }
}
