import CryptoKit
import Foundation
import MyPianoCore
import Observation

/// The song library: built-in songs, imported files, favourites, settings and practice history.
@MainActor
@Observable
final class LibraryModel {
    private(set) var database = LibraryDatabase()
    private(set) var lastError: String?
    /// Set by the File ▸ Import command; the main window presents the file picker.
    var isImporterPresented = false

    @ObservationIgnored private let store: LibraryFileStore
    @ObservationIgnored let songsFolder: URL
    @ObservationIgnored private let builtinFolder: URL?
    @ObservationIgnored private var cache: [String: Song] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = support.appendingPathComponent("MyPiano", isDirectory: true)
        store = LibraryFileStore(url: folder.appendingPathComponent("Library.json"))
        songsFolder = folder.appendingPathComponent("Songs", isDirectory: true)
        builtinFolder = Bundle.main.url(forResource: "BuiltinSongs", withExtension: nil)
        load()
    }

    // MARK: Loading

    private func load() {
        do {
            database = try store.load()
        } catch {
            lastError = String(localized: "La bibliothèque n'a pas pu être lue : \(error.localizedDescription)")
        }
        installBuiltinSongs()
    }

    /// Adds (or refreshes) the songs shipped with the app.
    private func installBuiltinSongs() {
        guard let builtinFolder,
              let data = try? Data(contentsOf: builtinFolder.appendingPathComponent("catalog.json")),
              let catalog = try? BuiltinCatalog.load(from: data) else { return }
        let languages = Locale.preferredLanguages
        var changed = false
        for entry in catalog.songs {
            let existing = database.song(entry.id)
            if let existing, existing.title == entry.title(preferredLanguages: languages) { continue }
            guard let song = try? SongLoader.load(contentsOf: builtinFolder.appendingPathComponent(entry.file)) else { continue }
            database.upsert(LibrarySong(
                id: entry.id, title: entry.title(preferredLanguages: languages), composer: entry.composer,
                source: .builtin, fileName: entry.file, duration: song.duration,
                difficulty: DifficultyEstimator.rating(for: song), license: entry.license
            ))
            cache[entry.id] = song
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        do {
            try store.save(database)
        } catch {
            lastError = String(localized: "La bibliothèque n'a pas pu être enregistrée : \(error.localizedDescription)")
        }
    }

    // MARK: Songs

    func fileURL(for entry: LibrarySong) -> URL? {
        switch entry.source {
        case .builtin: builtinFolder?.appendingPathComponent(entry.fileName)
        case .imported, .watched: songsFolder.appendingPathComponent(entry.fileName)
        }
    }

    func song(for id: String) throws -> Song {
        if let cached = cache[id] { return cached }
        guard let entry = database.song(id), let url = fileURL(for: entry) else { throw CocoaError(.fileNoSuchFile) }
        let song = try SongLoader.load(contentsOf: url)
        cache[id] = song
        return song
    }

    func songs(in category: LibraryCategory, matching search: String) -> [LibrarySong] {
        database.songs(in: category, matching: search)
    }

    func toggleFavorite(_ id: String) {
        database.update(id) { $0.isFavorite.toggle() }
        save()
    }

    func saveSettings(_ settings: PracticeSettings, for id: String) {
        database.update(id) { $0.settings = settings }
        // Sliders change settings many times a second: write once they settle.
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func record(_ summary: SessionSummary, for id: String) {
        database.record(summary, for: id)
        save()
    }

    func remove(_ id: String) {
        guard let entry = database.song(id), entry.source != .builtin else { return }
        if let url = fileURL(for: entry) { try? FileManager.default.removeItem(at: url) }
        database.remove(id)
        cache[id] = nil
        save()
    }

    // MARK: Import

    struct ImportResult {
        var added: [LibrarySong] = []
        var duplicates: [(file: String, id: String)] = []
        var failures: [(file: String, reason: String)] = []

        /// The song to show when a single file was imported (or was already in the library).
        var singleSongID: String? {
            let ids = added.map(\.id) + duplicates.map(\.id)
            return ids.count == 1 && failures.isEmpty ? ids[0] : nil
        }
    }

    /// A message about the last import, shown by the main window.
    struct ImportNotice: Identifiable {
        let id = UUID()
        let message: String
    }

    var importNotice: ImportNotice?
    /// A song the main window should select (after an import).
    var songToSelect: String?

    /// Imports files and reports the outcome to the main window: the first new song is selected,
    /// and a message lists duplicates and failures.
    @discardableResult
    func importAndReport(_ urls: [URL]) -> ImportResult {
        let result = importFiles(urls)
        songToSelect = result.added.first?.id ?? result.duplicates.first?.id
        var lines: [String] = []
        if !result.added.isEmpty { lines.append(String(localized: "\(result.added.count) morceau(x) ajouté(s).")) }
        if !result.duplicates.isEmpty {
            lines.append(String(localized: "Déjà dans la bibliothèque : \(result.duplicates.map(\.file).joined(separator: ", "))"))
        }
        for failure in result.failures { lines.append("\(failure.file) : \(failure.reason)") }
        if result.added.count + result.duplicates.count > 1 || !result.failures.isEmpty {
            importNotice = ImportNotice(message: lines.joined(separator: "\n"))
        }
        return result
    }

    /// Copies supported files into the library. Files already imported are recognised by content.
    @discardableResult
    func importFiles(_ urls: [URL], source: SongSource = .imported) -> ImportResult {
        var result = ImportResult()
        try? FileManager.default.createDirectory(at: songsFolder, withIntermediateDirectories: true)
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            do {
                let data = try Data(contentsOf: url)
                let song = try SongLoader.load(data: data, fileExtension: url.pathExtension)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if let existing = database.songs.first(where: { $0.contentHash == hash }) {
                    result.duplicates.append((name, existing.id))
                    continue
                }
                let id = "imported." + UUID().uuidString
                let ext = url.pathExtension.isEmpty ? "mid" : url.pathExtension.lowercased()
                let fileName = id + "." + ext
                try data.write(to: songsFolder.appendingPathComponent(fileName), options: .atomic)
                var entry = LibrarySong(
                    id: id, title: song.title ?? url.deletingPathExtension().lastPathComponent, composer: song.composer,
                    source: source, fileName: fileName, duration: song.duration,
                    difficulty: DifficultyEstimator.rating(for: song), contentHash: hash
                )
                entry.sourcePath = source == .watched ? url.path : nil
                database.upsert(entry)
                cache[id] = song
                result.added.append(entry)
            } catch let error as SongLoadingError {
                result.failures.append((name, Self.describe(error)))
            } catch {
                result.failures.append((name, error.localizedDescription))
            }
        }
        if !result.added.isEmpty { save() }
        return result
    }

    static func describe(_ error: SongLoadingError) -> String {
        switch error {
        case .unsupportedFormat:
            String(localized: "Ce format de fichier n'est pas pris en charge (MIDI ou MusicXML attendu).")
        case .midi(.notAMIDIFile), .midi(.truncated), .midi(.noTracks):
            String(localized: "Le fichier MIDI est invalide ou incomplet.")
        case .midi(.unsupportedTimeDivision), .midi(.unsupportedFormat):
            String(localized: "Ce type de fichier MIDI n'est pas pris en charge.")
        case .musicXML(.noNotes):
            String(localized: "La partition ne contient aucune note.")
        case .musicXML(.notMusicXML):
            String(localized: "Ce fichier XML n'est pas une partition MusicXML.")
        case .musicXML:
            String(localized: "La partition MusicXML est invalide.")
        }
    }
}
