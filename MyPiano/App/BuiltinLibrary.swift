import Foundation
import MyPianoCore

/// A song shipped in the app bundle, ready to practise.
struct BuiltinSong: Identifiable {
    let id: String
    let title: String
    let composer: String?
    let song: Song
}

enum BuiltinLibrary {
    /// Loads and parses every built-in song listed in `BuiltinSongs/catalog.json`.
    static func load() -> [BuiltinSong] {
        guard let folder = Bundle.main.url(forResource: "BuiltinSongs", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("catalog.json")),
              let catalog = try? BuiltinCatalog.load(from: data)
        else { return [] }
        let languages = Locale.preferredLanguages
        return catalog.songs.compactMap { entry in
            guard let song = try? SongLoader.load(contentsOf: folder.appendingPathComponent(entry.file)) else { return nil }
            return BuiltinSong(id: entry.id, title: entry.title(preferredLanguages: languages), composer: entry.composer, song: song)
        }
    }
}
