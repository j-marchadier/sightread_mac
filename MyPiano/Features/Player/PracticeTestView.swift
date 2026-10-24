import MyPianoCore
import SwiftUI

/// Temporary practice window (Phase 5): plays a built-in song with the real engine, without the
/// final visualizations, to check timing, wait mode, loop, metronome and scoring with a keyboard.
struct PracticeTestView: View {
    @Environment(AppModel.self) private var model
    @State private var songs: [BuiltinSong] = []
    @State private var selectedID: String?
    @State private var player: PlayerViewModel?

    var body: some View {
        Form {
            Section {
                Picker("Morceau", selection: $selectedID) {
                    Text("Choisir…").tag(String?.none)
                    ForEach(songs) { song in
                        Text(song.composer.map { "\(song.title) — \($0)" } ?? song.title).tag(Optional(song.id))
                    }
                }
            }
            if let player {
                PracticeControls(player: player)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 620)
        .task {
            model.start()
            if songs.isEmpty { songs = BuiltinLibrary.load() }
        }
        .onChange(of: selectedID) { _, id in open(id) }
        .onDisappear {
            player?.close()
            player = nil
        }
    }

    private func open(_ id: String?) {
        player?.close()
        player = nil
        guard let id, let entry = songs.first(where: { $0.id == id }) else { return }
        player = PlayerViewModel(song: entry.song, title: entry.title, audio: model.audio, input: model.practiceInput)
    }
}

private struct PracticeControls: View {
    let player: PlayerViewModel

    var body: some View {
        Section("Lecture") {
            HStack(spacing: 16) {
                Button { player.restart() } label: { Image(systemName: "backward.end.fill") }
                    .help("Revenir au début")
                Button { player.previousMeasure() } label: { Image(systemName: "backward.fill") }
                    .help("Mesure précédente")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(player.isPlaying ? "Pause" : "Lecture")
                Button { player.nextMeasure() } label: { Image(systemName: "forward.fill") }
                    .help("Mesure suivante")
                Spacer()
                Text(timeText).monospacedDigit()
            }
            LabeledContent("Mesure", value: "\(player.snapshot.measureIndex + 1) / \(player.song.measures.count)")
            LabeledContent("État", value: stateText)
        }

        Section("Réglages") {
            Picker("Mode", selection: binding(\.mode)) {
                Text("Apprendre").tag(PracticeMode.learn)
                Text("Attendre").tag(PracticeMode.wait)
                Text("Écouter").tag(PracticeMode.listen)
            }
            .pickerStyle(.segmented)
            Picker("Vitesse", selection: binding(\.speed)) {
                ForEach(PracticeSettings.speedPresets, id: \.self) { speed in
                    Text(speed.formatted(.percent.precision(.fractionLength(0)))).tag(speed)
                }
            }
            Toggle("Main gauche", isOn: handBinding(.left))
            Toggle("Main droite", isOn: handBinding(.right))
            Toggle("Ne pas jouer ma partie", isOn: binding(\.muteMyPart))
            Toggle("Décompte", isOn: binding(\.countdownEnabled))
            Toggle("Métronome", isOn: binding(\.metronome.isEnabled))
            Toggle("Son sur les fausses notes", isOn: binding(\.wrongNoteSound))
            Toggle("Boucler les 4 premières mesures", isOn: loopBinding)
        }

        Section("Statistiques") {
            let stats = player.snapshot.stats
            LabeledContent("Précision", value: "\(stats.accuracyPercent) %")
            LabeledContent("Parfait", value: "\(stats.perfect)")
            LabeledContent("Bien", value: "\(stats.good)")
            LabeledContent("Manquées", value: "\(stats.missed)")
            LabeledContent("Fausses notes", value: "\(stats.wrong)")
            LabeledContent("Série (meilleure)", value: "\(stats.streak) (\(stats.bestStreak))")
            LabeledContent("Score", value: "\(stats.score)")
        }
    }

    private var timeText: String {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 1))
        let current = Duration.milliseconds(Int(player.snapshot.time * 1000)).formatted(format)
        let total = Duration.milliseconds(Int(player.song.duration * 1000)).formatted(format)
        return "\(current) / \(total)"
    }

    private var stateText: String {
        let snapshot = player.snapshot
        switch snapshot.state {
        case .paused: return String(localized: "En pause")
        case .finished: return String(localized: "Terminé")
        case .countingDown: return String(localized: "Décompte : \(snapshot.countdown?.remaining ?? 0)")
        case .playing: return snapshot.isWaiting ? String(localized: "En attente de la bonne note") : String(localized: "Lecture")
        }
    }

    private func binding<Value: Sendable>(_ keyPath: WritableKeyPath<PracticeSettings, Value>) -> Binding<Value> {
        Binding(get: { player.settings[keyPath: keyPath] }, set: { value in player.update { $0[keyPath: keyPath] = value } })
    }

    private func handBinding(_ hand: Hand) -> Binding<Bool> {
        Binding(
            get: { player.settings.hands.contains(hand) },
            set: { isOn in player.update { if isOn { $0.hands.insert(hand) } else { $0.hands.remove(hand) } } }
        )
    }

    private var loopBinding: Binding<Bool> {
        Binding(
            get: { player.settings.loop != nil },
            set: { isOn in
                let last = min(3, player.song.measures.count - 1)
                player.update { $0.loop = isOn ? LoopRange(firstMeasure: 0, lastMeasure: last) : nil }
            }
        )
    }
}
