import PianissimacCore
import PianissimacRendering
import SwiftUI

/// Play anything: the notes rise from the keys as they are played.
struct FreePlayView: View {
    @Environment(AppModel.self) private var model
    @State private var display = Preferences.display

    var body: some View {
        FallingNotesView(
            scene: scene,
            frame: { [pressedKeys = model.pressedKeys, liveNotes = model.liveNotes] in
                let now = HostTime.now
                return FallingNotesFrame(time: 0, pressedKeys: Set(pressedKeys.current.keys),
                                         liveNotes: liveNotes.notes(at: now), hostTime: now)
            },
            onKey: { pitch, isDown in model.playKey(pitch, isDown: isDown) }
        )
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle("Jeu libre")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $display.showsNoteNames) { Label("Noms des notes", systemImage: "textformat") }
                    .help("Noms des notes sur les touches")
                Toggle(isOn: $display.fullKeyboard) { Label("Clavier complet", systemImage: "pianokeys") }
                    .help("Afficher les 88 touches")
                Button { model.liveNotes.clear() } label: { Label("Effacer", systemImage: "trash") }
                    .help("Effacer les notes jouées")
            }
        }
        .onDisappear { model.liveNotes.clear() }
    }

    private var scene: FallingNotesScene {
        let song = Song.empty
        return FallingNotesScene(
            song: song, noteHands: [], activeHands: [.left, .right], labels: nil,
            keyNames: display.showsNoteNames ? display.naming : nil, transpose: 0,
            keyboardRange: display.fullKeyboard ? PianoKeys.lowest...PianoKeys.highest : 36...96,
            pointsPerSecond: display.pointsPerSecond
        )
    }
}
