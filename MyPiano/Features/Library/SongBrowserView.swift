import MyPianoCore
import SwiftUI

/// How the library shows its songs.
enum LibraryLayout: String {
    case grid
    case list
}

/// Songs of a library category as a grid of covers or a sortable table, searchable.
struct SongBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let category: LibraryCategory
    @Binding var selection: LibrarySong.ID?
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\LibrarySong.title, comparator: .localizedStandard)]
    @State private var songToRemove: LibrarySong?
    @State private var songToEdit: String?
    @AppStorage("library.layout") private var layout = LibraryLayout.grid

    var body: some View {
        let songs = model.library.songs(in: category, matching: search).sorted(using: sortOrder)
        Group {
            switch layout {
            case .grid: grid(songs)
            case .list: table(songs)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: Text("Titre ou compositeur"))
        .navigationTitle(title)
        .navigationSplitViewColumnWidth(min: 380, ideal: 560)
        .toolbar {
            ToolbarItem {
                Picker("Présentation", selection: $layout) {
                    Label("Grille", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                    Label("Liste", systemImage: "list.bullet").tag(LibraryLayout.list)
                }
                .pickerStyle(.segmented)
                .help("Afficher les pochettes ou la liste")
            }
            if layout == .grid {
                ToolbarItem {
                    Menu {
                        Picker("Trier par", selection: sortKey) {
                            Text("Titre").tag(SortKey.title)
                            Text("Compositeur").tag(SortKey.composer)
                            Text("Difficulté").tag(SortKey.difficulty)
                            Text("Dernière séance").tag(SortKey.lastPlayed)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("Trier", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Trier les morceaux")
                }
            }
            ToolbarSpacer(.fixed)
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

    private func grid(_ songs: [LibrarySong]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20)], alignment: .leading, spacing: 24) {
                ForEach(songs) { song in
                    SongTile(song: song, isSelected: selection == song.id)
                        .onTapGesture(count: 2) { play(song.id) }
                        .simultaneousGesture(TapGesture().onEnded { selection = song.id })
                        .contextMenu { songMenu(song.id) }
                        .accessibilityAction { play(song.id) }
                }
            }
            .padding(20)
        }
    }

    private func table(_ songs: [LibrarySong]) -> some View {
        Table(songs, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Titre", value: \.title, comparator: .localizedStandard) { song in
                HStack(spacing: 8) {
                    SongArtwork(song: song, cornerRadius: 4).frame(width: 28, height: 28)
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
            if let id = ids.first { songMenu(id) }
        } primaryAction: { ids in
            if let id = ids.first { play(id) }
        }
    }

    @ViewBuilder
    private func songMenu(_ id: String) -> some View {
        if let song = model.library.database.song(id) {
            Button("Jouer") { play(id) }
            Button(song.isFavorite ? LocalizedStringKey("Retirer des favoris") : "Ajouter aux favoris") { model.library.toggleFavorite(id) }
            Button("Modifier…") { songToEdit = id }
            if song.source != .builtin {
                Divider()
                Button("Supprimer de la bibliothèque…", role: .destructive) { songToRemove = song }
            }
        }
    }

    private enum SortKey: Hashable { case title, composer, difficulty, lastPlayed }

    /// The grid has no column headers: its sort order is picked from a menu.
    private var sortKey: Binding<SortKey> {
        Binding(get: {
            switch sortOrder.first?.keyPath {
            case \LibrarySong.composerSortKey: .composer
            case \LibrarySong.difficulty: .difficulty
            case \LibrarySong.lastPlayedSortKey: .lastPlayed
            default: .title
            }
        }, set: { key in
            switch key {
            case .title: sortOrder = [KeyPathComparator(\LibrarySong.title, comparator: .localizedStandard)]
            case .composer: sortOrder = [KeyPathComparator(\LibrarySong.composerSortKey, comparator: .localizedStandard)]
            case .difficulty: sortOrder = [KeyPathComparator(\LibrarySong.difficulty)]
            case .lastPlayed: sortOrder = [KeyPathComparator(\LibrarySong.lastPlayedSortKey, order: .reverse)]
            }
        })
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

/// A cover with its title and composer, as in a music app's album grid.
private struct SongTile: View {
    let song: LibrarySong
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SongArtwork(song: song, cornerRadius: 10)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .opacity(isSelected ? 1 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    if song.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .glassEffect(.regular, in: .circle)
                            .padding(6)
                    }
                }
            Text(song.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(song.composer ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(song.composer.map { "\(song.title), \($0)" } ?? song.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
    var filled: Color = .accentColor
    var empty: Color = .secondary.opacity(0.25)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= level ? filled : empty)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Difficulté \(level) sur 5"))
    }
}
