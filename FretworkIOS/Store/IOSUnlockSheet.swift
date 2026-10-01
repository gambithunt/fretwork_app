import SwiftUI

/// The native one-time-unlock sheet. The nav bar owns the title, the body
/// scrolls (so it survives large Dynamic Type on the smallest iPhone), and the
/// buy/restore actions stay pinned in a bottom safe-area inset.
///
/// No forced colour scheme here: it inherits the root's dark scheme, and the
/// light snapshot scenario flips the root so the sheet can be reviewed in both.
struct IOSUnlockSheet: View {
    let store: IOSUnlockStore
    /// Called when a purchase or restore flips `isUnlocked`; dismisses and
    /// navigates into the module that opened the sheet.
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    terms
                    moduleList
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Unlock all lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .tint(NotePalette.accent)
        .task {
            if store.displayPrice == nil {
                await store.loadProduct()
            }
        }
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { onUnlocked() }
        }
    }

    private var intro: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(NotePalette.accent)
            Text("Unlocks all nine learning modules, forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var terms: some View {
        Label("One-time purchase · No subscription · Works offline", systemImage: "checkmark.seal.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var moduleList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(UnlockCatalog.lockedModules) { module in
                HStack(spacing: 10) {
                    Image(systemName: module.symbol)
                        .frame(width: 24)
                        .foregroundStyle(NotePalette.accent)
                    Text(module.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.purchase() }
            } label: {
                HStack {
                    if store.isPurchasing {
                        ProgressView()
                    } else if let price = store.displayPrice {
                        Text("Unlock — \(price)")
                            .fontWeight(.semibold)
                    } else {
                        Text("Unlock")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(NotePalette.backdrop)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(store.isPurchasing || store.displayPrice == nil)

            Button("Restore Purchases") {
                Task { await store.restore() }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(store.isPurchasing)

            if let message = store.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
