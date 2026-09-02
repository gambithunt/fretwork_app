import CoreAudio
import SwiftUI

struct DevicePickerView: View {
    let title: String
    let devices: [AudioDevice]
    let selection: AudioDeviceID?
    let onSelect: (AudioDeviceID?) -> Void

    var body: some View {
        Picker(title, selection: Binding(get: { selection }, set: onSelect)) {
            Text("Choose device").tag(AudioDeviceID?.none)
            ForEach(devices) { device in Text(device.name).tag(Optional(device.id)) }
        }
        .labelsHidden()
        // The settings form owns the width. A picker that sizes itself to its
        // current device name makes every other control look misaligned as
        // "GP-200 Audio" becomes "MacBook Pro Speakers".
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
