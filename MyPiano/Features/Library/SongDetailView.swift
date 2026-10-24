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

    /// Title band on a gradient that runs under the glass toolbar.
    private var hero: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.largeTitle.bold())
                if let composer = song.composer {
                    Text(composer).font(.title3).foregroundStyle(.white.opacity(0.8))
                }
                DifficultyView(level: song.difficulty, filled: .white, empty: .white.opacity(0.3)).padding(.top, 4)
            }
            .foregroundStyle(.white)
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
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottom)
        .background {
            LinearGradient(colors: [Color("HeroStart"), Color("HeroEnd")], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "music.quarternote.3")
                        .font(.system(size: 150, weight: .light))
                        .foregroundStyle(.white.opacity(0.14))
                        .padding(.top, 40)
                        .padding(.trailing, 28)
                        .accessibilityHidden(true)
                }
                .backgroundExtensionEffect()
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
