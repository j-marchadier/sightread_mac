import MyPianoCore
import SwiftUI

/// Songs of a library category in a sortable, searchable table.
struct SongBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let category: LibraryCategory
    @Binding var selection: LibrarySong.ID?
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\LibrarySong.title, comparator: .localizedStandard)]
    @State private var songToRemove: LibrarySong?
    @State private var songToEdit: String?

    var body: some View {
        let songs = model.library.songs(in: category, matching: search).sorted(using: sortOrder)
        Table(songs, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Titre", value: \.title, comparator: .localizedStandard) { song in
                HStack(spacing: 6) {
                    Text(song.title)
                    if song.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small)
                            .accessibilityLabel(Text("Favori"))
                    }
                }
            }
            TableColumn("Compositeur", value: \.composerSortKey, comparator: .localizedStandard) { song in
                Text(song.composer ?? "").foregroundStyle(.secondary)
            }
            TableColumn("Durée", value: \.duration) { song in
                Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("Difficulté", value: \.difficulty) { song in
                DifficultyView(level: song.difficulty)
            }
            .width(min: 70, ideal: 80, max: 100)
            TableColumn("Joué", value: \.lastPlayedSortKey) { song in
                if let lastPlayed = song.lastPlayed {
                    Text(lastPlayed, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                } else {
                    Text("Jamais").foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 110)
        }
        .contextMenu(forSelectionType: LibrarySong.ID.self) { ids in
            if let id = ids.first, let song = model.library.database.song(id) {
                Button("Jouer") { play(id) }
                Button(song.isFavorite ? LocalizedStringKey("Retirer des favoris") : "Ajouter aux favoris") { model.library.toggleFavorite(id) }
                Button("Modifier…") { songToEdit = id }
                if song.source != .builtin {
                    Divider()
                    Button("Supprimer de la bibliothèque…", role: .destructive) { songToRemove = song }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { play(id) }
        }
        .searchable(text: $search, placement: .toolbar, prompt: Text("Titre ou compositeur"))
        .navigationTitle(title)
        .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        .toolbar {
            ToolbarItem {
                Button { model.library.isImporterPresented = true } label: {
                    Label("Importer", systemImage: "plus")
                }
                .help("Importer des fichiers MIDI ou MusicXML")
            }
        }
        .overlay {
            if songs.isEmpty { emptyState }
        }
        .sheet(item: Binding(get: { songToEdit.map(EditedSong.init) }, set: { songToEdit = $0?.id })) { edited in
            SongEditorView(songID: edited.id)
        }
        .confirmationDialog("Supprimer « \(songToRemove?.title ?? "") » ?", isPresented: Binding(
            get: { songToRemove != nil }, set: { if !$0 { songToRemove = nil } }
        )) {
            Button("Supprimer", role: .destructive) {
                if let id = songToRemove?.id {
                    if selection == id { selection = nil }
                    model.library.remove(id)
                }
            }
        } message: {
            Text("Le fichier et l'historique de pratique seront supprimés.")
        }
    }

    private func play(_ id: String) {
        openWindow(id: WindowID.player, value: PlayerTarget.song(id: id))
    }

    private var title: String {
        switch category {
        case .all: String(localized: "Bibliothèque")
        case .recent: String(localized: "Récents")
        case .favorites: String(localized: "Favoris")
        case .imported: String(localized: "Importés")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch category {
            case .recent:
                ContentUnavailableView("Aucun morceau joué", systemImage: "clock",
                                       description: Text("Les morceaux que vous travaillez apparaîtront ici."))
            case .favorites:
                ContentUnavailableView("Aucun favori", systemImage: "star",
                                       description: Text("Ajoutez un morceau aux favoris depuis sa fiche ou son menu contextuel."))
            case .imported:
                ContentUnavailableView {
                    Label("Aucun morceau importé", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Importez vos fichiers MIDI ou MusicXML.")
                } actions: {
                    Button("Importer…") { model.library.isImporterPresented = true }
                    Button("Trouver des partitions…") { openWindow(id: WindowID.scoreSources) }
                }
            case .all:
                ContentUnavailableView("Bibliothèque vide", systemImage: "music.note.list")
            }
        }
    }
}

private struct EditedSong: Identifiable {
    let id: String
}

extension LibrarySong {
    var composerSortKey: String { composer ?? "" }
    var lastPlayedSortKey: Date { lastPlayed ?? .distantPast }
}

/// Difficulty from 1 to 5 as filled dots.
struct DifficultyView: View {
    let level: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= level ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Difficulté \(level) sur 5"))
    }
}
