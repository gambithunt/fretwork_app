import SwiftUI

/// Drives a dot's entry and exit: an absolute position, a scale and an
/// opacity, so the two ends of the transition are stated outright rather than
/// as an offset layered on top of a separately-fixed position.
struct DotMotionModifier: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .position(x: x, y: y)
    }
}
