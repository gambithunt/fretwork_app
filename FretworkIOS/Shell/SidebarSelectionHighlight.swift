import SwiftUI

/// The one selection highlight that slides between the iPad sidebar's rows.
///
/// Each selectable row's background carries this shape, re-parented with
/// `matchedGeometryEffect` (see `IOSAppRootView.sidebarRow`), so the highlight
/// slides from the old row to the new one under `FretworkMotion.gravity` instead
/// of jumping. The fill matches the system's Liquid Glass selection: ~11% of
/// the primary colour over the sidebar's material — measured (45, 46, 47) over a
/// (19, 20, 21) dark backdrop — drawn as the same rounded rect with a continuous
/// corner (squircle), matching the system shape's measured corner profile.
struct SidebarSelectionHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 37, style: .continuous)
            // `.primary` rather than `.white`: the selection tint is white in
            // dark mode (same 11% glass as before) and black in light mode, so
            // the capsule stays visible on a light sidebar.
            .fill(Color.primary.opacity(0.11))
    }
}


