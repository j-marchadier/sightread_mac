import MyPianoCore
import SwiftUI

/// Temporary start screen until the library window lands (Phase 7):
/// it proves the app bundle, its resources and the core module work together.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var songCount: Int?

    var body: some View {
        ContentUnavailableView {
            Label("MyPiano", systemImage: "pianokeys")
        } description: {
            VStack(spacing: 6) {
                if let songCount {
                    Text("\(songCount) morceaux intégrés prêts à être joués.")
                } else {
                    Text("Chargement de la bibliothèque…")
                }
                switch model.midi.status {
                case .noKeyboard: Text("Aucun clavier MIDI connecté.")
                case let .connected(names): Text("Clavier connecté : \(names.joined(separator: ", "))")
                }
            }
        } actions: {
            Button("Tester le clavier et le son…") { openWindow(id: WindowID.keyboardDiagnostics) }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task { songCount = Self.loadBuiltinSongCount() }
    }

    private static func loadBuiltinSongCount() -> Int {
        guard let folder = Bundle.main.url(forResource: "BuiltinSongs", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("catalog.json")),
              let catalog = try? BuiltinCatalog.load(from: data)
        else { return 0 }
        return catalog.songs.filter { entry in
            (try? SongLoader.load(contentsOf: folder.appendingPathComponent(entry.file))) != nil
        }.count
    }
}
