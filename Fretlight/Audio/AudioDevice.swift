import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable, Sendable {
    /// Valid only for as long as the device stays connected — Core Audio
    /// reassigns these freely across unplug/replug and reboot, so an ID is
    /// safe to hold for the lifetime of a selection but never to persist.
    let id: AudioDeviceID
    let name: String
    /// Stable across reconnects and reboots. This is what gets saved.
    let uid: String
}

enum AudioDeviceEnumerator {
    static func inputDevices() -> [AudioDevice] {
        devices(scope: kAudioDevicePropertyScopeInput)
    }

    static func outputDevices() -> [AudioDevice] {
        devices(scope: kAudioDevicePropertyScopeOutput)
    }

    private static func devices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasChannels(id, scope: scope), let name = deviceName(id), let uid = deviceUID(id) else { return nil }
            return AudioDevice(id: id, name: name, uid: uid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func nominalSampleRate(_ id: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    private static func hasChannels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }
}

extension AudioDeviceEnumerator {
    /// A device that exposes both input and output streams under a single
    /// `AudioDeviceID` can be driven by one AUHAL in full duplex — capture and
    /// playback then share an IO cycle and a clock. Devices that split their
    /// two directions across separate IDs (the built-in mic and speakers, most
    /// aggregates) cannot, and must fall back to the two-engine path.
    static func isDuplexCapable(_ id: AudioDeviceID) -> Bool {
        channelCount(id, scope: kAudioDevicePropertyScopeInput) > 0
            && channelCount(id, scope: kAudioDevicePropertyScopeOutput) > 0
    }

    static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func bufferFrameSize(_ id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &frames) == noErr, frames > 0 else { return nil }
        return frames
    }

    /// Requests a hardware IO buffer of `frames`, clamped to what the device
    /// advertises. This is the same knob as a DAW's "buffer size" preference,
    /// and it is the only way to reduce the fixed ~11.6ms per direction that a
    /// stock 512-frame buffer costs — no amount of work further up the graph
    /// can recover it. Returns the size actually in force afterwards.
    ///
    /// Deliberately best-effort: the property is shared by every client of the
    /// device and some drivers refuse to change it while in use. A refusal is
    /// not an error, it just means we live with the buffer we were given.
    @discardableResult
    static func setBufferFrameSize(_ frames: UInt32, on id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else {
            return bufferFrameSize(id)
        }
        var requested = frames
        if let range = bufferFrameSizeRange(id) {
            requested = min(max(frames, UInt32(range.mMinimum)), UInt32(range.mMaximum))
        }
        // Already there: skip the set. Writing this property restarts the
        // device's IO for every client attached to it, so it is worth not
        // doing on every engine rebuild during a recovery loop.
        if let current = bufferFrameSize(id), current == requested { return current }
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &requested)
        return bufferFrameSize(id)
    }

    private static func bufferFrameSizeRange(_ id: AudioDeviceID) -> AudioValueRange? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSizeRange, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &range) == noErr, range.mMaximum > 0 else { return nil }
        return range
    }
}
