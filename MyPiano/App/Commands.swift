import MyPianoCore
import SwiftUI

struct NewExerciseAction {
    let isAvailable: Bool
    let run: () -> Void
}

private struct PlayerKey: FocusedValueKey { typealias Value = PlayerViewModel }
private struct ShowsInspectorKey: FocusedValueKey { typealias Value = Binding<Bool> }
private struct NewExerciseKey: FocusedValueKey { typealias Value = NewExerciseAction }

extension FocusedValues {
    /// The practice session of the frontmost player window.
    var player: PlayerViewModel? {
        get { self[PlayerKey.self] }
        set { self[PlayerKey.self] = newValue }
    }

    var showsInspector: Binding<Bool>? {
        get { self[ShowsInspectorKey.self] }
        set { self[ShowsInspectorKey.self] = newValue }
    }

    var newExercise: NewExerciseAction? {
        get { self[NewExerciseKey.self] }
        set { self[NewExerciseKey.self] = newValue }
    }
}

/// File, Lecture, Présentation and Help menu items.
struct MyPianoCommands: Commands {
    let model: AppModel
    @FocusedValue(\.player) private var player
    @FocusedValue(\.showsInspector) private var showsInspector
    @FocusedValue(\.newExercise) private var newExercise
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Importer…") {
                openWindow(id: WindowID.main)
                model.library.isImporterPresented = true
            }
            .keyboardShortcut("o")
            Button("Jeu libre") { openWindow(id: WindowID.freePlay) }
                .keyboardShortcut("j", modifiers: [.command, .shift])
        }

        CommandMenu("Lecture") {
            Button(player?.isPlaying == true ? LocalizedStringKey("Pause") : "Lecture") { player?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(player == nil)
            Button("Revenir au début") { player?.restart() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(player == nil)
            Button("Mesure précédente") { player?.previousMeasure() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(player == nil)
            Button("Mesure suivante") { player?.nextMeasure() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(player == nil)
            Divider()
            Button("Plus rapide") { player?.changeSpeed(by: 0.05) }
                .keyboardShortcut("+", modifiers: [.command])
                .disabled(player == nil)
            Button("Plus lent") { player?.changeSpeed(by: -0.05) }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(player == nil)
            Button("Vitesse normale") { player?.update { $0.speed = 1 } }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(player == nil)
            Divider()
            Picker("Mode", selection: settingBinding(\.mode, default: .learn)) {
                Text("Apprendre").tag(PracticeMode.learn)
                Text("Attendre").tag(PracticeMode.wait)
                Text("Écouter").tag(PracticeMode.listen)
            }
            .disabled(player == nil)
            Toggle("Main gauche", isOn: handBinding(.left))
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(player == nil)
            Toggle("Main droite", isOn: handBinding(.right))
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(player == nil)
            Divider()
            Toggle("Boucle", isOn: Binding(get: { player?.settings.loop != nil }, set: { _ in player?.toggleLoop() }))
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(player == nil)
            Toggle("Métronome", isOn: settingBinding(\.metronome.isEnabled, default: false))
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(player == nil)
            if let newExercise, newExercise.isAvailable {
                Divider()
                Button("Nouvelle série", action: newExercise.run)
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        CommandGroup(before: .sidebar) {
            Picker("Visualisation", selection: displayBinding(\.visualization, default: .fallingNotes)) {
                Text("Notes qui tombent").tag(Visualization.fallingNotes)
                Text("Partition simplifiée").tag(Visualization.simplifiedSheet)
                Text("Partition rythmique").tag(Visualization.rhythmicSheet)
            }
            .disabled(player == nil)
            Toggle("Noms des notes", isOn: displayBinding(\.showsNoteNames, default: false))
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(player == nil)
            Toggle("Clavier complet", isOn: displayBinding(\.fullKeyboard, default: true))
                .disabled(player == nil)
            Toggle("Réglages du morceau", isOn: showsInspector ?? .constant(false))
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(showsInspector == nil)
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Bienvenue dans MyPiano") { openWindow(id: WindowID.welcome) }
        }
    }

    private func settingBinding<Value: Sendable>(_ keyPath: WritableKeyPath<PracticeSettings, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { player?.settings[keyPath: keyPath] ?? value }, set: { new in player?.update { $0[keyPath: keyPath] = new } })
    }

    private func displayBinding<Value: Sendable>(_ keyPath: WritableKeyPath<DisplayOptions, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { player?.display[keyPath: keyPath] ?? value }, set: { new in player?.updateDisplay { $0[keyPath: keyPath] = new } })
    }

    private func handBinding(_ hand: Hand) -> Binding<Bool> {
        Binding(get: { player?.settings.hands.contains(hand) ?? false }, set: { _ in player?.toggleHand(hand) })
    }
}
