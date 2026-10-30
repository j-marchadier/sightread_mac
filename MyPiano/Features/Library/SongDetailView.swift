import MyPianoCore
import SwiftUI

/// A song's details: progress, practice history, favourite and play button.
struct SongDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let song: LibrarySong
    @State private var isEditing = false
    @State private var scoreRequest: ScoreExportRequest?

    var body: some View {
        let progress = model.library.database.progress(for: song.id)
        let records = model.library.database.records(for: song.id)
        ScrollView {
            hero
            VStack(alignment: .leading, spacing: 20) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    GridRow {
                        fact("Durée", Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                        fact("Séances", "\(progress.sessions)")
                    }
                    GridRow {
                        fact("Meilleure précision", progress.bestAccuracy.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                        fact("Temps de pratique", Duration.seconds(progress.practiceSeconds)
                            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .show(length: 1))))
                    }
                }
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Historique").font(.headline)
                        ForEach(records.prefix(20)) { record in
                            HistoryRow(summary: record.summary)
                            Divider()
                        }
                    }
                }
                if let license = song.license {
                    Text(license).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(song.title)
        .sheet(isPresented: $isEditing) { SongEditorView(songID: song.id) }
        .scoreExport(request: $scoreRequest) { [library = model.library, id = song.id] in
            try library.printableScore(for: id)
        }
        .toolbar {
            ToolbarItem {
                Button { openWindow(id: WindowID.scoreEditor, value: song.id) } label: {
                    Label("Modifier les notes", systemImage: "music.note.list")
                }
                .help("Modifier les notes sur la partition")
            }
            ToolbarItem {
                Button { isEditing = true } label: { Label("Modifier", systemImage: "pencil") }
                    .help("Modifier le titre, la difficulté et les mains")
                    .keyboardShortcut("e")
            }
            ToolbarItem {
                Button { model.library.toggleFavorite(song.id) } label: {
                    Label(song.isFavorite ? LocalizedStringKey("Retirer des favoris") : "Ajouter aux favoris",
                          systemImage: song.isFavorite ? "star.fill" : "star")
                }
                .help(song.isFavorite ? LocalizedStringKey("Retirer des favoris") : "Ajouter aux favoris")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                ScoreExportMenu(request: $scoreRequest)
            }
        }
    }

    /// Cover and title on a band coloured by the cover, running under the glass toolbar.
    private var hero: some View {
        HStack(alignment: .bottom, spacing: 20) {
            SongArtwork(song: song, store: model.library.artwork, cornerRadius: 12)
                .frame(width: 168, height: 168)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.largeTitle.bold())
                if let composer = song.composer {
                    Text(composer).font(.title3).foregroundStyle(.white.opacity(0.8))
                }
                DifficultyView(level: song.difficulty, filled: .white, empty: .white.opacity(0.3)).padding(.top, 4)
                if model.library.hasEdits(song.id) {
                    Label("Notes modifiées", systemImage: "music.note.list")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: .capsule)
                        .padding(.top, 4)
                        .help("Les notes de ce morceau ont été modifiées. « Modifier les notes » permet de rétablir l'original.")
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.2), radius: 4)
            Spacer()
            Button {
                openWindow(id: WindowID.player, value: PlayerTarget.song(id: song.id))
            } label: {
                Label("Jouer", systemImage: "play.fill").padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .padding(.top, 52)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .background {
            heroBackground
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                .backgroundExtensionEffect()
        }
    }

    /// The custom cover blurred, or the generated cover's gradient.
    @ViewBuilder
    private var heroBackground: some View {
        if let image = model.library.artwork.image(for: song.id) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 40, opaque: true)
                .clipped()
        } else {
            ArtworkPalette.palette(title: song.title, composer: song.composer).gradient
        }
    }

    private func fact(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let summary: SessionSummary

    var body: some View {
        HStack {
            Text(summary.startedAt, format: .dateTime.day().month().hour().minute())
            Spacer()
            Text(modeName).foregroundStyle(.secondary)
            Text(summary.speed.formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).monospacedDigit()
            if summary.mode != .listen {
                Text("\(summary.stats.accuracyPercent) %").monospacedDigit().frame(width: 50, alignment: .trailing)
            } else {
                Text("–").frame(width: 50, alignment: .trailing)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var modeName: String {
        switch summary.mode {
        case .learn: String(localized: "Apprendre")
        case .wait: String(localized: "Attendre")
        case .listen: String(localized: "Écouter")
        }
    }
}
