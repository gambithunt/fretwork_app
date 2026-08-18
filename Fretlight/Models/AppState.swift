import Foundation
import Observation
import CoreAudio

@MainActor @Observable
final class AppState {
    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var selectedInputDeviceID: AudioDeviceID?
    var selectedOutputDeviceID: AudioDeviceID?
    var monitorMuted = true { didSet { applyMonitorVolume() } }
    var monitorVolume: Double = 0.8 { didSet { applyMonitorVolume() } }
    var display = PitchDisplayState()
    var errorMessage: String?
    private let audioEngine = AudioEngine()

    init() {
        refreshDevices()
        audioEngine.onUpdate = { [weak self] update in
            Task { @MainActor [weak self] in
                self?.display = update
            }
        }
        audioEngine.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.errorMessage = message
            }
        }
        audioEngine.onRecovered = { [weak self] in
            Task { @MainActor [weak self] in
                self?.errorMessage = nil
            }
        }
        if let saved = UserDefaults.standard.object(forKey: "selectedInputDeviceID") as? UInt32,
           inputDevices.contains(where: { $0.id == saved }) {
            selectedInputDeviceID = saved
        } else {
            selectedInputDeviceID = inputDevices.first?.id
        }
        if let saved = UserDefaults.standard.object(forKey: "selectedOutputDeviceID") as? UInt32,
           outputDevices.contains(where: { $0.id == saved }) {
            selectedOutputDeviceID = saved
        } else {
            selectedOutputDeviceID = outputDevices.first?.id
        }
    }

    func refreshDevices() {
        inputDevices = AudioDeviceEnumerator.inputDevices()
        outputDevices = AudioDeviceEnumerator.outputDevices()
        if let selectedInputDeviceID, !inputDevices.contains(where: { $0.id == selectedInputDeviceID }) {
            self.selectedInputDeviceID = inputDevices.first?.id
        }
        if let selectedOutputDeviceID, !outputDevices.contains(where: { $0.id == selectedOutputDeviceID }) {
            self.selectedOutputDeviceID = outputDevices.first?.id
        }
    }

    func selectInputDevice(_ id: AudioDeviceID?) {
        selectedInputDeviceID = id
        if let id { UserDefaults.standard.set(id, forKey: "selectedInputDeviceID") }
        start()
    }

    func selectOutputDevice(_ id: AudioDeviceID?) {
        selectedOutputDeviceID = id
        if let id { UserDefaults.standard.set(id, forKey: "selectedOutputDeviceID") }
        start()
    }

    private func applyMonitorVolume() {
        audioEngine.setMonitorVolume(monitorMuted ? 0 : Float(monitorVolume))
    }

    func start() {
        guard let selectedInputDeviceID, let selectedOutputDeviceID else { return }
        errorMessage = nil
        audioEngine.start(inputDeviceID: selectedInputDeviceID, outputDeviceID: selectedOutputDeviceID, monitorVolume: monitorMuted ? 0 : Float(monitorVolume))
    }

    func retryAudio() { start() }

    deinit { audioEngine.stop() }
}
