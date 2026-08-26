import SwiftUI
import XCTest
@testable import Fretwork

/// The palette mirrors the web app's CSS custom properties. Sharing it is what
/// makes a shape look identical in both apps, so the values are compared
/// against the web's stylesheet rather than eyeballed.
final class NotePaletteTests: XCTestCase {
    /// A struct rather than a tuple: tuples are not `Equatable`, so
    /// `XCTAssertEqual` cannot compare two of them.
    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var description: String { String(format: "#%02x%02x%02x", r, g, b) }
    }

    private func components(_ color: Color) -> RGB {
        let native = NSColor(color).usingColorSpace(.sRGB)!
        return RGB(r: Int((native.redComponent * 255).rounded()),
                   g: Int((native.greenComponent * 255).rounded()),
                   b: Int((native.blueComponent * 255).rounded()))
    }

    /// The web's values, mirrored here as literals so the everyday suite is
    /// hermetic. `testEveryPitchClassMatchesTheWebStylesheet` compares these
    /// against the live stylesheet when explicitly asked to.
    private let expected: [String: RGB] = [
        "--fw-note-0": RGB(r: 0xe5, g: 0x56, b: 0x4e),
        "--fw-note-1": RGB(r: 0xe0, g: 0x7a, b: 0x3e),
        "--fw-note-2": RGB(r: 0xd6, g: 0xa2, b: 0x3c),
        "--fw-note-3": RGB(r: 0xc2, g: 0xbf, b: 0x4a),
        "--fw-note-4": RGB(r: 0x5b, g: 0xbf, b: 0x5b),
        "--fw-note-5": RGB(r: 0x3f, g: 0xbf, b: 0x8c),
        "--fw-note-6": RGB(r: 0x3f, g: 0xb6, b: 0xc4),
        "--fw-note-7": RGB(r: 0x3f, g: 0x8f, b: 0xd8),
        "--fw-note-8": RGB(r: 0x6a, g: 0x78, b: 0xdd),
        "--fw-note-9": RGB(r: 0x9a, g: 0x6f, b: 0xdd),
        "--fw-note-10": RGB(r: 0xc4, g: 0x5f, b: 0xc4),
        "--fw-note-11": RGB(r: 0xe0, g: 0x5a, b: 0x8f),
        "--fw-root": RGB(r: 0x1d, g: 0x9e, b: 0x75),
        "--fw-interval": RGB(r: 0x7f, g: 0x77, b: 0xdd),
        "--fw-fifth": RGB(r: 0xd8, g: 0x5a, b: 0x30),
        "--fw-degree": RGB(r: 0x37, g: 0x8a, b: 0xdd),
        "--fw-penta": RGB(r: 0xe8, g: 0xc3, b: 0x4a),
        "--fw-tone-dim": RGB(r: 0x8a, g: 0x8a, b: 0x99),
        "--fw-accent": RGB(r: 0x5d, g: 0xca, b: 0xa5)
    ]

    /// Parses the live stylesheet — **only** when `FRETWORK_WEB_REPO` points at
    /// the web checkout, following the opt-in convention
    /// `DetectionBoardSnapshotTests` already uses.
    ///
    /// Reading the sibling repo unconditionally is what made this suite hang:
    /// the test host is a sandboxed app, and a read outside its container needs
    /// a Documents-folder grant. In a headless `xcodebuild` run there is nobody
    /// to answer that prompt, so the read blocks *indefinitely* — the whole
    /// suite stalled after 260 tests with no failure and no message. A unit
    /// test must not reach outside the test bundle for a file it needs.
    private func webVariables() throws -> [String: RGB] {
        guard let root = ProcessInfo.processInfo.environment["FRETWORK_WEB_REPO"] else {
            throw XCTSkip("set TEST_RUNNER_FRETWORK_WEB_REPO to the web checkout to compare against the live stylesheet")
        }
        let css = URL(fileURLWithPath: root).appendingPathComponent("src/app.css")
        guard FileManager.default.fileExists(atPath: css.path) else {
            throw XCTSkip("no app.css under \(root)")
        }
        var found: [String: RGB] = [:]
        for line in try String(contentsOf: css, encoding: .utf8).split(separator: "\n") {
            guard let nameRange = line.range(of: "--fw-[a-z0-9-]+", options: .regularExpression),
                  // `.regularExpression` on both: without it this is a literal
                  // substring search for the pattern text, which never matches
                  // and silently yields an empty table — a comparison against
                  // nothing, which passes or fails for the wrong reason.
                  let hexRange = line.range(of: "#[0-9a-fA-F]{6}", options: .regularExpression)
            else { continue }
            let hex = UInt32(line[hexRange].dropFirst(), radix: 16)!
            found[String(line[nameRange])] = RGB(r: Int((hex >> 16) & 0xff), g: Int((hex >> 8) & 0xff), b: Int(hex & 0xff))
        }
        return found
    }

    /// The everyday check: the palette matches the values mirrored from the
    /// web. Hermetic — no file reads.
    func testEveryPitchClassMatchesTheMirroredWebValues() throws {
        for pitchClass in 0..<12 {
            let want = try XCTUnwrap(expected["--fw-note-\(pitchClass)"])
            XCTAssertEqual(components(NotePalette.color(forPitchClass: pitchClass)), want, "pitch class \(pitchClass)")
        }
    }

    func testRoleColoursMatchTheMirroredWebValues() throws {
        let mapping: [(NotePalette.Role, String)] = [
            (.root, "--fw-root"), (.third, "--fw-interval"), (.fifth, "--fw-fifth"),
            (.degree, "--fw-degree"), (.pentatonic, "--fw-penta"), (.outsideShape, "--fw-tone-dim")
        ]
        for (role, variable) in mapping {
            XCTAssertEqual(components(NotePalette.color(for: role)), try XCTUnwrap(expected[variable]), variable)
        }
        XCTAssertEqual(components(NotePalette.accent), try XCTUnwrap(expected["--fw-accent"]))
    }

    /// The drift check against the live web repo. Opt-in.
    func testTheMirroredValuesStillMatchTheWebStylesheet() throws {
        let web = try webVariables()
        // An empty table would make every comparison below vacuous, so the
        // parse is asserted before anything is compared against it.
        XCTAssertGreaterThan(web.count, 20, "the stylesheet parsed to \(web.count) variables; the regex is not matching")
        for (variable, want) in expected {
            XCTAssertEqual(web[variable], want, "\(variable) has drifted from the web app")
        }
    }



    // MARK: - Keying by pitch class

    /// The whole reason for re-keying: a string key cannot survive the app
    /// spelling a note `A♯` in one place and `B♭` in another.
    func testBothSpellingsOfANoteGetTheSameColour() {
        XCTAssertEqual(components(NotePalette.color(for: "A♯")), components(NotePalette.color(for: "B♭")))
        XCTAssertEqual(components(NotePalette.color(for: "C♯")), components(NotePalette.color(for: "D♭")))
        XCTAssertEqual(components(NotePalette.color(for: "A#")), components(NotePalette.color(for: "Bb")))
    }

    func testNaturalsParseAndKeepTheirLetter() {
        for (name, pitchClass) in [("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)] {
            XCTAssertEqual(PitchClass(name: name)?.value, pitchClass, "\(name)")
            XCTAssertEqual(components(NotePalette.color(for: name)),
                           components(NotePalette.color(forPitchClass: pitchClass)))
        }
    }

    func testAnUnparseableNameFallsBackRatherThanTrapping() {
        XCTAssertNil(PitchClass(name: "H"))
        XCTAssertNil(PitchClass(name: ""))
        XCTAssertNil(PitchClass(name: "wat"))
        XCTAssertEqual(components(NotePalette.color(for: "H")), components(Color.orange))
    }

    func testPitchClassWrapsRatherThanCrashing() {
        XCTAssertEqual(components(NotePalette.color(forPitchClass: 12)), components(NotePalette.color(forPitchClass: 0)))
        XCTAssertEqual(components(NotePalette.color(forPitchClass: -1)), components(NotePalette.color(forPitchClass: 11)))
    }

    /// Role colours must be distinguishable from one another — they are the
    /// lesson's vocabulary, and two roles that look alike teach nothing.
    func testEveryRoleIsADistinctColour() {
        let all = NotePalette.Role.allCases.map { components(NotePalette.color(for: $0)).description }
        XCTAssertEqual(Set(all).count, NotePalette.Role.allCases.count)
    }
}
