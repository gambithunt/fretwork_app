import SwiftUI

/// Pure, side-effect-free marker values for the iOS target.
///
/// Tests assert against these instead of rendering, so importing and linking the
/// app module cannot accidentally touch audio hardware.
enum IOSScaffoldPhase {
    static let phase0Identifier = "workstream-009-phase-0"
    static let phase1Identifier = "workstream-009-phase-1-simulator-first"
}

/// Kept as a tiny inert view for Phase 0 identifier coverage and previews. The
/// app entry point now hosts `Phase1HarnessView`.
struct IOSScaffoldView: View {
    var body: some View {
        Text("Fretwork iOS harness")
            .font(.headline)
            .padding()
    }
}

#Preview {
    IOSScaffoldView()
}
