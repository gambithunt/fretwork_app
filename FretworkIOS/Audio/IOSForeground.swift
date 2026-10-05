import UIKit

/// Foreground/background seam for the activation policy (C-12: audio only
/// while foreground-active).
///
/// `IOSAudioController` holds one of these and rebuilds/tears down its graph
/// from the callbacks. A protocol rather than `NotificationCenter` directly so
/// the controller's policy is unit-testable with a fake that fires
/// synchronously.
@MainActor
protocol IOSForegroundObserving: AnyObject {
    var onForegroundChange: ((Bool) -> Void)? { get set }
}

/// Production wrapper over the two `UIApplication` lifecycle notifications,
/// plus one catch-up read of the current activation state at construction.
///
/// Deliberately ignores `UIApplication.willResignActiveNotification`: it fires
/// transiently for the microphone permission alert and for Control Center, and
/// stopping capture there is exactly the Phase 1 failure that was excluded
/// ("stops on `.background`; does not stop on `.inactive`"). `didBecomeActive`
/// and `didEnterBackground` are the pair that matches the policy.
///
/// **Why the catch-up read matters (iOS app on Mac).** A `didBecomeActive`
/// notification is only useful if this observer already exists when it is
/// posted. On iPhone the SwiftUI root (and therefore `AppState`/
/// `IOSAudioController`, which owns this observer) is built during
/// `scene(_:willConnectTo:)`, before the app becomes active, so the
/// notification is never missed. On an Apple-silicon Mac running the iOS
/// binary ("Designed for iPad") `UIKitMacHelper` completes the app's
/// `BG -> FG-I -> FG-A` transition about 18 ms *before* the controller is
/// constructed — measured, `AVAudioSession_MacOS` init logged ~18 ms after
/// `Scene state changed to foreground active` — so the only `didBecomeActive`
/// has already fired and is missed. Without this read `foregroundActive` stays
/// `false` forever and every graph build is skipped, which made the Notes
/// module permanently mute ("Notes will not sound until audio is ready.").
///
/// The delivery is deferred one main-actor turn because `onForegroundChange` is
/// assigned by `IOSAudioController.init` *after* this observer is constructed;
/// a synchronous call here would reach a nil closure. A duplicate `true` is
/// harmless: `IOSAudioController.updateAudioNeed()` only rebuilds when the
/// running leg differs from the wanted one.
///
/// `@MainActor` classes are implicitly `Sendable`, so the `[weak self]` capture
/// in the `NotificationCenter` blocks is safe under strict concurrency; the
/// `Task { @MainActor in … }` is the only hop, because the block itself is not
/// statically known to run on the main actor even with `queue: .main`.
@MainActor
final class SystemIOSForegroundObserver: IOSForegroundObserving {
    var onForegroundChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let becameActive = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onForegroundChange?(true) }
        }
        let enteredBackground = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onForegroundChange?(false) }
        }
        observers = [becameActive, enteredBackground]

        // Catch-up for an activation that happened before this observer
        // existed (see the type doc). Deferred so it runs after
        // `IOSAudioController.init` has installed its `onForegroundChange`.
        Task { @MainActor [weak self] in
            guard let self, UIApplication.shared.applicationState == .active else { return }
            self.onForegroundChange?(true)
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
