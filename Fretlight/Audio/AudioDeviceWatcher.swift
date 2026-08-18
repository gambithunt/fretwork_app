import CoreAudio
import Foundation

/// Watches Core Audio's system-wide device list and calls back whenever it
/// changes — plugging in or unplugging any input/output hardware — so the
/// UI's device pickers can pick up a newly connected interface without the
/// user having to notice and manually trigger a rescan.
///
/// This only refreshes what's *available to select*; it deliberately
/// doesn't touch the currently selected device or restart the engine —
/// that's a separate, already-handled concern (AudioEngine's own
/// reconnect/circuit-breaker logic) for when the device *in use* drops out.
final class AudioDeviceWatcher: @unchecked Sendable {
    /// The Core Audio listener block has to be created at init, before
    /// `self` is fully initialized — so it can't capture `self` directly.
    /// It captures this plain box instead, and `onChange` reads/writes
    /// through it, letting an owner (whose own callback needs `self`)
    /// assign it after construction.
    private final class CallbackBox: @unchecked Sendable {
        var callback: (@Sendable () -> Void)?
    }

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let box = CallbackBox()
    // Add and Remove must be given the identical block reference to
    // correctly pair up and unregister; a freshly-made closure at deinit
    // would silently fail to remove the listener.
    private let listenerBlock: AudioObjectPropertyListenerBlock

    var onChange: (@Sendable () -> Void)? {
        get { box.callback }
        set { box.callback = newValue }
    }

    init() {
        let box = self.box
        let block: AudioObjectPropertyListenerBlock = { _, _ in box.callback?() }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listenerBlock)
    }
}
