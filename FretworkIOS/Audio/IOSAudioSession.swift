import AVFoundation
import Foundation

/// A system interruption (a call, Siri), reduced to `Sendable` values before it
/// crosses to the main actor.
struct IOSAudioInterruption: Sendable {
    enum Kind: Sendable { case began, ended }
    let kind: Kind
    /// `AVAudioSession.InterruptionOptions.shouldResume`, meaningful only on
    /// `.ended`.
    let shouldResume: Bool
}

/// `AVAudioSession.RouteChangeReason` reduced to the cases the controller
/// actually distinguishes. Everything else collapses to `.unknown`.
enum IOSAudioRouteChangeReason: Sendable {
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case unknown
}

/// The session seam. `IOSAudioController` never names `AVAudioSession`; this is
/// the one boundary that does, so the controller's lifecycle/activation policy
/// can be exercised in the default suite with `FakeIOSAudioSession` and no real
/// audio hardware (C-11).
///
/// Handlers are delivered on the main actor. The production wrapper does the
/// hop from the `NotificationCenter` thread internally and converts the
/// notification payloads into the small `Sendable` structs above first.
@MainActor
protocol IOSAudioSessionControlling: AnyObject {
    var recordPermission: IOSAudioRecordPermission { get }
    /// Requests the grant when `.undetermined` and resolves with the outcome.
    func requestRecordPermission() async -> Bool

    /// `.playAndRecord`/`.measurement`/`[.defaultToSpeaker]` for listening,
    /// `.playback`/`.default`/`[]` for sample playback without the mic.
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool) throws

    var sampleRate: Double { get }
    var inputLatency: TimeInterval { get }
    var ioBufferDuration: TimeInterval { get }

    var onInterruption: ((IOSAudioInterruption) -> Void)? { get set }
    var onRouteChange: ((IOSAudioRouteChangeReason) -> Void)? { get set }
    var onMediaServicesReset: (() -> Void)? { get set }
}

/// Production wrapper around `AVAudioApplication` (permission) and
/// `AVAudioSession.sharedInstance()` (category/activation/notifications).
///
/// The notification blocks run on whatever thread posted them (`queue: nil`),
/// read only value types, then hop once to the main actor. No realtime block is
/// built here, so there is no NONSENDABLE trap to avoid — but the delegation,
/// rather than touching `AVAudioSession` from the controller, is also what keeps
/// the controller testable.
@MainActor
final class SystemIOSAudioSession: IOSAudioSessionControlling {
    var onInterruption: ((IOSAudioInterruption) -> Void)?
    var onRouteChange: ((IOSAudioRouteChangeReason) -> Void)?
    var onMediaServicesReset: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let session = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let info = notification.userInfo
            guard let rawType = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }
            let rawOptions = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            Task { @MainActor [weak self] in
                switch type {
                case .began:
                    self?.onInterruption?(IOSAudioInterruption(kind: .began, shouldResume: false))
                case .ended:
                    self?.onInterruption?(IOSAudioInterruption(kind: .ended, shouldResume: shouldResume))
                @unknown default:
                    break
                }
            }
        }

        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            let mapped = Self.mapRouteChangeReason(reason)
            Task { @MainActor [weak self] in self?.onRouteChange?(mapped) }
        }

        let mediaReset = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onMediaServicesReset?() }
        }

        observers = [interruption, routeChange, mediaReset]
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var recordPermission: IOSAudioRecordPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .denied
        }
    }

    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        try AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool) throws {
        if active {
            try AVAudioSession.sharedInstance().setActive(true)
        } else {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    var sampleRate: Double { AVAudioSession.sharedInstance().sampleRate }
    var inputLatency: TimeInterval { AVAudioSession.sharedInstance().inputLatency }
    var ioBufferDuration: TimeInterval { AVAudioSession.sharedInstance().ioBufferDuration }

    static func mapRouteChangeReason(_ reason: AVAudioSession.RouteChangeReason?) -> IOSAudioRouteChangeReason {
        switch reason {
        case .newDeviceAvailable: .newDeviceAvailable
        case .oldDeviceUnavailable: .oldDeviceUnavailable
        case .categoryChange: .categoryChange
        case .override: .override
        default: .unknown
        }
    }
}
