import MyPianoCore
import MyPianoRendering
import SwiftUI

/// The practice screen: visualization under a floating glass control bar, toolbar and inspector.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    let player: PlayerViewModel
    let isExercise: Bool
    let onNewExercise: () -> Void
    @State private var showsInspector = false

    var body: some View {
        visualization
            .overlay { CountdownBadge(remaining: player.snapshot.countdown?.remaining) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerControlBar(player: player)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        .navigationTitle(player.title)
        .navigationSubtitle(player.subtitle ?? "")
        .toolbar { toolbarContent }
        .inspector(isPresented: $showsInspector) {
            PlayerInspector(player: player)
                .inspectorColumnWidth(min: 270, ideal: 300, max: 380)
        }
        .sheet(isPresented: Binding(get: { player.finishedSummary != nil }, set: { if !$0 { player.finishedSummary = nil } })) {
            if let summary = player.finishedSummary {
                SessionSummaryView(summary: summary, isExercise: isExercise) { action in
                    player.finishedSummary = nil
                    switch action {
                    case .again: player.restart(); player.togglePlayback()
                    case .newExercise: onNewExercise()
                    case .close: break
                    }
                }
            }
        }
        .focusedSceneValue(\.player, player)
        .focusedSceneValue(\.showsInspector, $showsInspector)
        .focusedSceneValue(\.newExercise, NewExerciseAction(isAvailable: isExercise, run: onNewExercise))
    }

    @ViewBuilder
    private var visualization: some View {
        let frame: @MainActor () -> FallingNotesFrame = { [pressedKeys = model.pressedKeys] in player.frame(pressedKeys: pressedKeys) }
        if let sheet = player.sheetScene, player.display.visualization == .pageSheet {
            SheetPageView(scene: sheet, frame: frame, onSeek: { player.seek(to: $0) },
                          onScrub: { player.scrub(by: $0) }, onScrubEnded: { player.endScrub() })
                .accessibilityValue(Text(positionDescription))
        } else if let sheet = player.sheetScene {
            SheetView(scene: sheet, frame: frame, onScrub: { player.scrub(by: $0) }, onScrubEnded: { player.endScrub() })
                .accessibilityValue(Text(positionDescription))
        } else {
            FallingNotesView(
                scene: player.scene, frame: frame,
                onKey: { pitch, isDown in model.playKey(pitch, isDown: isDown) },
                onScrub: { player.scrub(by: $0) },
                onScrubEnded: { player.endScrub() }
            )
            .accessibilityValue(Text(positionDescription))
        }
    }

    private var positionDescription: String {
        String(localized: "Mesure \(player.currentMeasureNumber) sur \(player.song.measures.count)")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isExercise {
            ToolbarItem {
                Button(action: onNewExercise) { Label("Nouvelle série", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Générer de nouvelles notes")
            }
            ToolbarSpacer(.fixed)
        }
        ToolbarItemGroup {
            Picker("Mode", selection: settingBinding(\.mode)) {
                Label("Apprendre", systemImage: "graduationcap").tag(PracticeMode.learn)
                Label("Attendre", systemImage: "hourglass").tag(PracticeMode.wait)
                Label("Écouter", systemImage: "headphones").tag(PracticeMode.listen)
            }
            .pickerStyle(.menu)
            .help("Mode de pratique")
            Menu {
                Toggle("Main gauche", isOn: handBinding(.left))
                Toggle("Main droite", isOn: handBinding(.right))
            } label: {
                Label(handsTitle, systemImage: "hand.raised")
            }
            .help("Mains à travailler")
            Menu {
                ForEach(PracticeSettings.speedPresets, id: \.self) { speed in
                    Button(speed.formatted(.percent.precision(.fractionLength(0)))) { player.update { $0.speed = speed } }
                }
            } label: {
                Label(player.settings.speed.formatted(.percent.precision(.fractionLength(0))), systemImage: "speedometer")
            }
            .help("Vitesse")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle(isOn: Binding(get: { player.settings.loop != nil }, set: { _ in player.toggleLoop() })) {
                Label("Boucle", systemImage: "repeat")
            }
            .help("Boucler des mesures")
            Toggle(isOn: settingBinding(\.metronome.isEnabled)) {
                Label("Métronome", systemImage: "metronome")
            }
            .help("Métronome")
            VolumeButton(metronome: settingBinding(\.metronome.volume))
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Picker("Visualisation", selection: displayBinding(\.visualization)) {
                Label("Notes qui tombent", systemImage: "pianokeys").tag(Visualization.fallingNotes)
                Label("Partition simplifiée", systemImage: "music.note").tag(Visualization.simplifiedSheet)
                Label("Partition rythmique", systemImage: "music.quarternote.3").tag(Visualization.rhythmicSheet)
                Label("Partition complète", systemImage: "doc.richtext").tag(Visualization.pageSheet)
            }
            .pickerStyle(.menu)
            .help("Visualisation")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button { showsInspector.toggle() } label: { Label("Réglages", systemImage: "sidebar.trailing") }
                .help("Afficher ou masquer les réglages")
        }
    }

    private var handsTitle: String {
        switch player.settings.hands {
        case [.left]: String(localized: "Main gauche")
        case [.right]: String(localized: "Main droite")
        default: String(localized: "Deux mains")
        }
    }

    private func settingBinding<Value: Sendable>(_ keyPath: WritableKeyPath<PracticeSettings, Value>) -> Binding<Value> {
        Binding(get: { player.settings[keyPath: keyPath] }, set: { value in player.update { $0[keyPath: keyPath] = value } })
    }

    private func displayBinding<Value: Sendable>(_ keyPath: WritableKeyPath<DisplayOptions, Value>) -> Binding<Value> {
        Binding(get: { player.display[keyPath: keyPath] }, set: { value in player.updateDisplay { $0[keyPath: keyPath] = value } })
    }

    private func handBinding(_ hand: Hand) -> Binding<Bool> {
        Binding(get: { player.settings.hands.contains(hand) }, set: { _ in player.toggleHand(hand) })
    }
}

/// Transport, measure timeline and position, floating in Liquid Glass above the bottom of the player.
struct PlayerControlBar: View {
    let player: PlayerViewModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    transportButton("Revenir au début", systemImage: "backward.end.fill") { player.restart() }
                    transportButton("Mesure précédente", systemImage: "backward.fill") { player.previousMeasure() }
                    transportButton("Mesure suivante", systemImage: "forward.fill") { player.nextMeasure() }
                }
                .padding(.horizontal, 6)
                .frame(height: 40)
                .glassEffect()

                Button { player.togglePlayback() } label: {
                    Label(player.isPlaying ? LocalizedStringKey("Pause") : "Lecture",
                          systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .help(player.isPlaying ? LocalizedStringKey("Pause") : "Lecture")

                MeasureTimelineView(player: player)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(height: 40)
                    .frame(minWidth: 200)
                    .glassEffect()

                PlaybackStatusView(player: player)
                    .frame(height: 40)
                    .glassEffect()
            }
        }
    }

    private func transportButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

/// The count-in before playback, in a glass bubble over the visualization.
struct CountdownBadge: View {
    let remaining: Int?

    var body: some View {
        ZStack {
            if let remaining {
                Text("\(remaining)")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .frame(width: 112, height: 112)
                    .glassEffect(.regular, in: .circle)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(Text("Décompte : \(remaining)"))
            }
        }
        .animation(.spring(duration: 0.3), value: remaining)
        .allowsHitTesting(false)
    }
}

/// Time, measure and state, at the end of the control bar.
struct PlaybackStatusView: View {
    let player: PlayerViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text(timeText).monospacedDigit()
            Text("Mesure \(player.currentMeasureNumber)/\(player.song.measures.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if player.snapshot.isWaiting {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                    .help("En attente de la bonne note")
            }
        }
        .font(.callout)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let format = Duration.TimeFormatStyle(pattern: .minuteSecond(padMinuteToLength: 1))
        let current = Duration.seconds(Int(player.snapshot.time)).formatted(format)
        let total = Duration.seconds(Int(player.song.duration.rounded(.up))).formatted(format)
        return "\(current) / \(total)"
    }
}
