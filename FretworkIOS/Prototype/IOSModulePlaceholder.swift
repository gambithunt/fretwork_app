import SwiftUI

/// Stands in for the nine modules this prototype does not implement yet. The
/// real title, blurb and icon come from the `LearningModule` catalogue, so the
/// list stays honest; only the body is a placeholder.
struct IOSModulePlaceholder: View {
    let module: LearningModule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(module.title)
                .font(.title2.weight(.semibold))
            Text(module.blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Not in this prototype", systemImage: "hammer")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(NotePalette.backdrop)
    }
}
