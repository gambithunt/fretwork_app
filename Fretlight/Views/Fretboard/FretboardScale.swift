import SwiftUI

/// Scales a fretboard's dots, labels and gutter. `1` is the phone/Mac size
/// every piece of the neck was tuned to; the iOS module scaffold raises it
/// when an iPad neck grows past that size, so the markers grow with the board
/// instead of reading as a phone board stretched over a desk.
extension EnvironmentValues {
    var fretworkFretboardScale: CGFloat {
        get { self[FretworkFretboardScaleKey.self] }
        set { self[FretworkFretboardScaleKey.self] = newValue }
    }
}

private struct FretworkFretboardScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
