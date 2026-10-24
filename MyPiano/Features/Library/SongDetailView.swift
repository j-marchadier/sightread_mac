import MyPianoCore
import SwiftUI

/// A song's details: progress, practice history, favourite and play button.
struct SongDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let song: LibrarySong
    @State private var isEditing = false

    var body: some View {
        let progress = model.library.database.progress(for: song.id)
        let records = model.library.database.records(for: song.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
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
        .navigationTitle(song.title)
        .sheet(isPresented: $isEditing) { SongEditorView(songID: song.id) }
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
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.largeTitle.bold())
                if let composer = song.composer {
                    Text(composer).font(.title3).foregroundStyle(.secondary)
                }
                DifficultyView(level: song.difficulty).padding(.top, 4)
            }
            Spacer()
            Button {
                openWindow(id: WindowID.player, value: PlayerTarget.song(id: song.id))
            } label: {
                Label("Jouer", systemImage: "play.fill").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
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
