import Foundation

/// The ten learning modules, in the web app's pedagogical order.
///
/// Mirrors `../fretwork/src/lib/modules/catalog.json`. Titles, blurbs, ids and
/// **order** are all part of that mirror: the two apps teach the same course,
/// and a module that is called one thing on the web and another here — or that
/// comes third in one and fifth in the other — is the same defect as a wrong
/// fret number, just harder to notice. `LearningModuleTests` compares this
/// against the JSON directly so the two cannot drift silently.
///
/// The order is pedagogical, not a gate. Everything is always open, exactly as
/// the web registry's own comment says.
enum LearningModule: String, CaseIterable, Identifiable, Sendable {
    case notes
    case intervals
    case octaves
    case triads
    case chords
    case pentatonic
    case scales
    case harmonizing
    case noteAssociation
    case circle

    var id: String { rawValue }

    /// The catalogue's `id`, which differs from the state id for
    /// `note-association` — the web keeps a kebab-case route id and a camelCase
    /// state key, and both are load-bearing on that side.
    var catalogID: String {
        switch self {
        case .noteAssociation: "note-association"
        default: rawValue
        }
    }

    var title: String {
        switch self {
        case .notes: "Notes on the fretboard"
        case .intervals: "Intervals"
        case .octaves: "Octaves"
        case .triads: "Triads"
        case .chords: "Major, minor & power chords"
        case .pentatonic: "Pentatonic scales"
        case .scales: "Scales — major & minor"
        case .harmonizing: "Harmonizing the scale"
        case .noteAssociation: "Note association"
        case .circle: "Circle of fifths"
        }
    }

    var blurb: String {
        switch self {
        case .notes: "Where every note lives. The foundation everything else sits on."
        case .intervals: "The distance between two notes — the building block of all theory."
        case .octaves: "Find the same note higher on the neck — a shape worth knowing cold."
        case .triads: "Three notes stacked in 3rds. How chords are actually built."
        case .chords: "Movable chord shapes, traced back to their root, 3rd and 5th when present."
        case .pentatonic: "Five positions with clear root indicators. The soloing workhorse."
        case .scales: "Full 7-note shapes and the intervals that define them."
        case .harmonizing: "Build the chords of a key by stacking scale tones."
        case .noteAssociation: "Put it together: the chord, the pentatonic to solo with, and the scale — all in one key."
        case .circle: "How all the keys relate — the map that ties it together."
        }
    }

    /// SF Symbol for the sidebar. Not from the web, which has no equivalent.
    var symbol: String {
        switch self {
        case .notes: "circle.grid.3x3"
        case .intervals: "arrow.left.and.right"
        case .octaves: "arrow.up.arrow.down"
        case .triads: "square.stack.3d.up"
        case .chords: "hand.raised.fingers.spread"
        case .pentatonic: "waveform.path"
        case .scales: "chart.line.uptrend.xyaxis"
        case .harmonizing: "square.stack"
        case .noteAssociation: "point.3.connected.trianglepath.dotted"
        case .circle: "circle.hexagongrid"
        }
    }

    /// How far up the neck this module's board goes. Explicit per module rather
    /// than one shared constant: the web uses 12 for most boards, 15 for
    /// Pentatonic and Chords, and 22 for Triads, and carrying that difference
    /// is what stops a shape being drawn off the end of its own board.
    var highestFret: Int {
        switch self {
        case .pentatonic, .chords: 15
        case .triads: 22
        default: 12
        }
    }
}

/// What the sidebar shows, in order: the listening screen first, then the
/// modules.
enum AppScreen: Hashable, Identifiable, Sendable {
    case listen
    case module(LearningModule)

    var id: String {
        switch self {
        case .listen: "listen"
        case .module(let module): module.id
        }
    }

    var title: String {
        switch self {
        case .listen: "Listen"
        case .module(let module): module.title
        }
    }

    var symbol: String {
        switch self {
        case .listen: "waveform.badge.magnifyingglass"
        case .module(let module): module.symbol
        }
    }

    /// Whether this screen consumes live detection. Only the listening screen
    /// does today; workstream 007's guided practice will add more, which is why
    /// this is a property of the screen rather than a check for `.listen`.
    var needsDetection: Bool {
        switch self {
        case .listen: true
        case .module: false
        }
    }

    static let all: [AppScreen] = [.listen] + LearningModule.allCases.map(AppScreen.module)
}
