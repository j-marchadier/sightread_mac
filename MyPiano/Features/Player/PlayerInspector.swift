import MyPianoCore
import SwiftUI

/// Settings and live statistics of the open song, in the inspector column.
struct PlayerInspector: View {
    let player: PlayerViewModel

    var body: some View {
        Form {
            Section("Statistiques") {
                StatsGrid(stats: player.stats, isJudged: player.settings.mode != .listen)
            }
            Section("Pratique") {
                Picker("Mode", selection: setting(\.mode)) {
                    Text("Apprendre").tag(PracticeMode.learn)
                    Text("Attendre").tag(PracticeMode.wait)
                    Text("Écouter").tag(PracticeMode.listen)
                }
                if player.settings.mode == .wait {
                    LabeledContent("Tolérance") {
                        Slider(value: setting(\.waitTolerance), in: PracticeSettings.waitToleranceRange, step: 0.05) {
                            Text("Tolérance")
                        } minimumValueLabel: {
                            Text("0 s")
                        } maximumValueLabel: {
                            Text("1 s")
                        }
                        .labelsHidden()
                    }
                    .help("Temps pendant lequel le morceau continue avant d'attendre la note")
                }
                LabeledContent("Vitesse") {
                    HStack {
                        Slider(value: setting(\.speed), in: PracticeSettings.speedRange, step: 0.05)
                            .labelsHidden()
                        Text(player.settings.speed.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Main gauche", isOn: hand(.left))
                Toggle("Main droite", isOn: hand(.right))
                Toggle("Décompte avant de jouer", isOn: setting(\.countdownEnabled))
                Toggle("Couper ma partie", isOn: setting(\.muteMyPart))
                    .help("N'entendre que ce que vous jouez pour les mains travaillées")
                Toggle("Son des fausses notes", isOn: setting(\.wrongNoteSound))
                Stepper(value: setting(\.transpose), in: PracticeSettings.transposeRange) {
                    LabeledContent("Transposition", value: transposeText)
                }
            }
            Section("Boucle") {
                Toggle("Boucler", isOn: Binding(get: { player.settings.loop != nil }, set: { _ in player.toggleLoop() }))
                if let loop = player.settings.loop {
                    let count = max(1, player.song.measures.count)
                    Stepper(value: loopBound(\.firstMeasure, loop: loop), in: 0...(count - 1)) {
                        LabeledContent("Première mesure", value: "\(loop.firstMeasure + 1)")
                    }
                    Stepper(value: loopBound(\.lastMeasure, loop: loop), in: 0...(count - 1)) {
                        LabeledContent("Dernière mesure", value: "\(loop.lastMeasure + 1)")
                    }
                }
            }
            Section("Métronome") {
                Toggle("Activer", isOn: setting(\.metronome.isEnabled))
                LabeledContent("Volume") {
                    Slider(value: setting(\.metronome.volume), in: 0...1).labelsHidden()
                }
                Picker("Battements", selection: setting(\.metronome.clicksPerBeat)) {
                    Text("Un par temps").tag(1.0)
                    Text("Deux par temps").tag(2.0)
                }
                Toggle("Accentuer le premier temps", isOn: setting(\.metronome.accentsFirstBeat))
            }
            Section("Affichage") {
                Toggle("Noms des notes", isOn: display(\.showsNoteNames))
                Picker("Nommer les notes", selection: display(\.naming)) {
                    Text("Do Ré Mi").tag(NoteNamingStyle.solfege)
                    Text("C D E").tag(NoteNamingStyle.letters)
                }
                Picker("Doigtés", selection: display(\.fingering)) {
                    Text("Masqués").tag(FingeringDisplay.off)
                    Text("Écrits seulement").tag(FingeringDisplay.written)
                    Text("Écrits et suggérés").tag(FingeringDisplay.all)
                }
                Toggle("Couleurs par note", isOn: display(\.coloredNotes))
                if player.display.visualization == .fallingNotes {
                    Toggle("Clavier complet", isOn: display(\.fullKeyboard))
                    LabeledContent("Défilement") {
                        Slider(value: display(\.pointsPerSecond), in: 100...450).labelsHidden()
                    }
                }
                if player.rhythmicFallback {
                    Label("Rythmes trop irréguliers : partition simplifiée affichée.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if player.song.tracks.count > 1 {
                Section("Pistes") {
                    ForEach(player.song.tracks.indices, id: \.self) { index in
                        TrackRow(player: player, index: index)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var transposeText: String {
        let value = player.settings.transpose
        return value == 0 ? String(localized: "Aucune") : String(localized: "\(value > 0 ? "+" : "")\(value) demi-tons")
    }

    private func setting<Value: Sendable>(_ keyPath: WritableKeyPath<PracticeSettings, Value>) -> Binding<Value> {
        Binding(get: { player.settings[keyPath: keyPath] }, set: { value in player.update { $0[keyPath: keyPath] = value } })
    }

    private func display<Value: Sendable>(_ keyPath: WritableKeyPath<DisplayOptions, Value>) -> Binding<Value> {
        Binding(get: { player.display[keyPath: keyPath] }, set: { value in player.updateDisplay { $0[keyPath: keyPath] = value } })
    }

    private func hand(_ hand: Hand) -> Binding<Bool> {
        Binding(get: { player.settings.hands.contains(hand) }, set: { _ in player.toggleHand(hand) })
    }

    private func loopBound(_ keyPath: WritableKeyPath<LoopRange, Int>, loop: LoopRange) -> Binding<Int> {
        Binding(get: { loop[keyPath: keyPath] }, set: { value in
            player.update { settings in
                guard var range = settings.loop else { return }
                range[keyPath: keyPath] = value
                if range.lastMeasure < range.firstMeasure {
                    if keyPath == \LoopRange.firstMeasure { range.lastMeasure = value } else { range.firstMeasure = value }
                }
                settings.loop = range
            }
        })
    }
}

/// Which hand plays a track, and whether it is heard.
private struct TrackRow: View {
    enum Role: Hashable { case left, right, accompaniment }

    let player: PlayerViewModel
    let index: Int

    var body: some View {
        let track = player.song.tracks[index]
        VStack(alignment: .leading, spacing: 6) {
            Text(track.name ?? String(localized: "Piste \(index + 1)")).font(.headline)
            HStack {
                Picker("Rôle", selection: role) {
                    Text("Main gauche").tag(Role.left)
                    Text("Main droite").tag(Role.right)
                    Text("Accompagnement").tag(Role.accompaniment)
                }
                .labelsHidden()
                Toggle(isOn: Binding(
                    get: { !player.settings.mutedTracks.contains(index) },
                    set: { audible in player.update { if audible { $0.mutedTracks.remove(index) } else { $0.mutedTracks.insert(index) } } }
                )) {
                    Image(systemName: "speaker.wave.2")
                }
                .toggleStyle(.button)
                .help("Entendre cette piste")
                .accessibilityLabel(Text("Entendre cette piste"))
            }
        }
    }

    private var role: Binding<Role> {
        Binding(get: {
            let assignment = player.settings.handAssignment
            if assignment.leftTracks.contains(index) { return .left }
            if assignment.rightTracks.contains(index) { return .right }
            return .accompaniment
        }, set: { role in
            player.update { settings in
                settings.handAssignment.leftTracks.remove(index)
                settings.handAssignment.rightTracks.remove(index)
                settings.handAssignment.splitTracks[index] = nil
                switch role {
                case .left: settings.handAssignment.leftTracks.insert(index)
                case .right: settings.handAssignment.rightTracks.insert(index)
                case .accompaniment: break
                }
            }
        })
    }
}

/// Hits, misses, accuracy and streak.
struct StatsGrid: View {
    let stats: PracticeStats
    let isJudged: Bool

    var body: some View {
        if isJudged {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    stat("Précision", "\(stats.accuracyPercent) %")
                    stat("Score", "\(stats.score)")
                }
                GridRow {
                    stat("Parfaites", "\(stats.perfect)", color: .green)
                    stat("Bonnes", "\(stats.good)", color: .teal)
                }
                GridRow {
                    stat("Manquées", "\(stats.missed)", color: .orange)
                    stat("Fausses", "\(stats.wrong)", color: .red)
                }
                GridRow {
                    stat("Série", "\(stats.streak)")
                    stat("Meilleure série", "\(stats.bestStreak)")
                }
            }
        } else {
            Text("Le mode Écouter ne compte pas les notes.").foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}
