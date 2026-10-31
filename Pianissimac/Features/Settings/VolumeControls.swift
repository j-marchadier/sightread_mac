import SwiftUI

/// Sliders for the app's volumes, used in the Settings window and in the player's volume popover.
struct VolumeControls: View {
    @Environment(AppModel.self) private var model
    /// The open song's metronome volume, when shown in a player.
    var metronome: Binding<Float>?

    var body: some View {
        @Bindable var model = model
        volumeRow("Volume général", systemImage: "speaker.wave.3", value: $model.masterVolume)
        volumeRow("Mon piano", systemImage: "pianokeys", value: $model.playerVolume)
        volumeRow("Morceau", systemImage: "music.note", value: $model.songVolume)
        if let metronome {
            volumeRow("Métronome", systemImage: "metronome", value: metronome)
        }
    }

    private func volumeRow(_ title: LocalizedStringKey, systemImage: String, value: Binding<Float>) -> some View {
        LabeledContent {
            Slider(value: value, in: 0...1) { Text(title) }
                .labelsHidden()
                .frame(minWidth: 140)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// Toolbar button opening the volume sliders.
struct VolumeButton: View {
    let metronome: Binding<Float>
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Label("Volume", systemImage: "speaker.wave.2")
        }
        .help("Volume")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Form { VolumeControls(metronome: metronome) }
                .formStyle(.grouped)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
