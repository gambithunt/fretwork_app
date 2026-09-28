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

/// Production wrapper over the two `UIApplication` lifecycle notifications.
///
/// Deliberately ignores `UIApplication.willResignActiveNotification`: it fires
/// transiently for the microphone permission alert and for Control Center, and
/// stopping capture there is exactly the Phase 1 failure that was excluded
/// ("stops on `.background`; does not stop on `.inactive`"). `didBecomeActive`
/// and `didEnterBackground` are the pair that matches the policy.
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
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
