import SwiftUI

/// iOS Settings (D-07): the instrument-and-room preferences that apply to
/// every screen — sensitivity, tuning, board orientation, and the live-note
/// and highlight toggles.
///
/// Deliberately absent (never disabled, just not here): device pickers,
/// monitoring, rescan, any device-path summary (D-07), and the anonymous
/// usage-data opt-in. The App Store build declares "Data Not Collected", so
/// the iOS app must not be able to reach the telemetry endpoint; the Mac
/// keeps that opt-in because it is not distributed through the store.
///
/// A native grouped `Form`. **No audio-rate reads here** — every bound value
/// changes only when the person changes it (D-08).
struct IOSSettingsSheet: View {
    @Bindable var state: AppState
    let unlockStore: IOSUnlockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text("\(Int((state.sensitivity * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $state.sensitivity, in: 0...1)
                    }
                } header: {
                    Text("Detection")
                } footer: {
                    Text("Strict rejects noisy signal; lenient catches quieter notes.")
                }

                Section("Instrument") {
                    Picker("Tuning", selection: $state.tuning) {
                        ForEach(Tunings.all, id: \.self) { tuning in
                            Text("\(tuning.name) · \(tuning.display)").tag(tuning)
                        }
                    }
                    Toggle("Low E on top", isOn: $state.isFretboardFlipped)
                }

                Section {
                    Toggle("Keep screen on while listening", isOn: $state.keepsScreenOnWhileListening)
                } footer: {
                    Text("The phone won't auto-lock while Fretwork is listening.")
                }

                Section {
                    Toggle("Live note on lessons", isOn: $state.showsLiveNoteOnModules)
                    Toggle("Highlight matching notes", isOn: $state.highlightsLiveNoteOnFretboards)
                        .disabled(!state.showsLiveNoteOnModules)
                } header: {
                    Text("Learning")
                } footer: {
                    Text("Show the detected note while using a lesson.")
                }

                Section {
                    Button {
                        Task { await unlockStore.restore() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            if unlockStore.isPurchasing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(unlockStore.isPurchasing)
                } header: {
                    Text("Unlock")
                } footer: {
                    Text(unlockStore.statusMessage ?? "Restore the one-time unlock if you already bought it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(NotePalette.accent)
        .preferredColorScheme(.dark)
    }
}
