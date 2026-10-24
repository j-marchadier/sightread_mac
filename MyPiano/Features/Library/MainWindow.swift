import MyPianoCore
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar sections of the main window.
enum SidebarItem: Hashable {
    case library(LibraryCategory)
    case noteReading
    case phrases
    case freePlay
}

/// The main window: sidebar, song list and song details.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.onboardingDone) private var onboardingDone = false
    @State private var selection: SidebarItem? = .library(.all)
    @State private var selectedSong: LibrarySong.ID?
    @State private var importMessage: String?

    var body: some View {
        @Bindable var library = model.library
        NavigationSplitView {
            List(selection: $selection) {
                Section("Morceaux") {
                    Label("Bibliothèque", systemImage: "music.note.list").tag(SidebarItem.library(.all))
                    Label("Récents", systemImage: "clock").tag(SidebarItem.library(.recent))
                    Label("Favoris", systemImage: "star").tag(SidebarItem.library(.favorites))
                    Label("Importés", systemImage: "square.and.arrow.down").tag(SidebarItem.library(.imported))
                }
                Section("Exercices") {
                    Label("Lecture de notes", systemImage: "eye").tag(SidebarItem.noteReading)
                    Label("Phrases", systemImage: "text.line.first.and.arrowtriangle.forward").tag(SidebarItem.phrases)
                }
                Section("Piano") {
                    Label("Jeu libre", systemImage: "pianokeys").tag(SidebarItem.freePlay)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) { KeyboardStatusView().padding(10) }
        } content: {
            switch selection ?? .library(.all) {
            case let .library(category):
                SongBrowserView(category: category, selection: $selectedSong)
            case .noteReading:
                NoteReadingSetupView()
            case .phrases:
                PhraseSetupView()
            case .freePlay:
                FreePlayLauncher()
            }
        } detail: {
            if case .library(_) = selection ?? .library(.all), let id = selectedSong, let song = model.library.database.song(id) {
                SongDetailView(song: song)
            } else {
                ContentUnavailableView("Aucun morceau sélectionné", systemImage: "music.note",
                                       description: Text("Choisissez un morceau pour voir vos progrès."))
            }
        }
        .fileImporter(isPresented: $library.isImporterPresented, allowedContentTypes: SongFileTypes.importable,
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { importFiles(urls) }
        }
        .alert("Importation", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .onAppear {
            if !onboardingDone { openWindow(id: WindowID.welcome) }
        }
    }

    private func importFiles(_ urls: [URL]) {
        let result = model.library.importFiles(urls)
        if let first = result.added.first {
            selection = .library(.imported)
            selectedSong = first.id
        }
        var lines: [String] = []
        if !result.added.isEmpty { lines.append(String(localized: "\(result.added.count) morceau(x) ajouté(s).")) }
        if !result.duplicates.isEmpty {
            lines.append(String(localized: "Déjà dans la bibliothèque : \(result.duplicates.joined(separator: ", "))"))
        }
        for failure in result.failures { lines.append("\(failure.file) : \(failure.reason)") }
        if !result.duplicates.isEmpty || !result.failures.isEmpty { importMessage = lines.joined(separator: "\n") }
    }
}

enum SongFileTypes {
    static let importable: [UTType] = [
        .midi,
        UTType(importedAs: "org.musicxml.musicxml", conformingTo: .xml),
        UTType(importedAs: "com.recordare.musicxml.compressed", conformingTo: .archive),
        .xml,
    ]
}

/// MIDI keyboard state at the bottom of the sidebar.
struct KeyboardStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button { openSettings() } label: {
            switch model.midi.status {
            case .noKeyboard:
                Label("Aucun clavier", systemImage: "pianokeys").foregroundStyle(.secondary)
            case let .connected(names):
                Label(names.first ?? "", systemImage: "pianokeys.inverse").foregroundStyle(.green)
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Réglages du clavier MIDI")
    }
}

/// The free-play entry in the main window.
private struct FreePlayLauncher: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentUnavailableView {
            Label("Jeu libre", systemImage: "pianokeys")
        } description: {
            Text("Jouez librement : les notes s'affichent au fur et à mesure.")
        } actions: {
            Button("Ouvrir le jeu libre") { openWindow(id: WindowID.freePlay) }
                .buttonStyle(.borderedProminent)
        }
    }
}
