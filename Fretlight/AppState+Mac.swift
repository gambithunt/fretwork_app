import Foundation

extension AppState {
    /// macOS default: a real HAL engine behind the shared seam. Preserves the
    /// `AppState()` call sites in `FretlightApp` and the macOS tests.
    convenience init() {
        let store = PracticeStateStore()
        self.init(audio: MacAudioController(store: store), store: store)
    }

    /// Mac-only views and tests reach the device/monitor/direct-path surface
    /// through this cast. Nil under a non-Mac `AudioControlling` (or a test
    /// fake), which is why every call site treats it as optional.
    var macAudio: MacAudioController? { audio as? MacAudioController }
}
