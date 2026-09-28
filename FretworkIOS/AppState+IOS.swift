import Foundation

extension AppState {
    /// iOS default: the `AVAudioSession`-backed controller behind the shared
    /// seam. Mirrors `AppState+Mac` (which is excluded from the iOS target, so
    /// the two never coexist in one module).
    ///
    /// `IOSAudioController` takes no `PracticeStateStore` — it has no device
    /// UIDs to persist — so the store is created here and handed only to
    /// `AppState`, which owns sensitivity, tuning and the other preferences.
    convenience init() {
        let store = PracticeStateStore()
        self.init(audio: IOSAudioController(), store: store)
    }

    /// iOS-only views and tests reach the richer iOS status surface through
    /// this cast, exactly as Mac views reach `macAudio`. Nil under a non-iOS
    /// controller (or a test fake).
    var iosAudio: IOSAudioController? { audio as? IOSAudioController }
}
