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
        .frame(maxWidth: 260)
    }
}
