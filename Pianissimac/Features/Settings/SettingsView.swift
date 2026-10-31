import PianissimacCore
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            KeyboardDiagnosticsView(part: .keyboard)
                .tabItem { Label("Clavier MIDI", systemImage: "pianokeys") }
            KeyboardDiagnosticsView(part: .audio)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            LibrarySettingsView()
                .tabItem { Label("Bibliothèque", systemImage: "books.vertical") }
            DisplaySettingsView()
                .tabItem { Label("Affichage", systemImage: "eye") }
            PracticeSettingsView()
                .tabItem { Label("Pratique", systemImage: "graduationcap") }
        }
        .frame(width: 540, height: 560)
    }
}

private struct DisplaySettingsView: View {
    @AppStorage(PreferenceKey.noteNaming) private var naming = NoteNamingStyle.solfege
    @AppStorage(PreferenceKey.visualization) private var visualization = Visualization.fallingNotes
    @AppStorage(PreferenceKey.showsNoteNames) private var showsNoteNames = false
    @AppStorage(PreferenceKey.coloredNotes) private var coloredNotes = false
    @AppStorage(PreferenceKey.fullKeyboard) private var fullKeyboard = true
    @AppStorage(PreferenceKey.fallingSpeed) private var fallingSpeed = 220.0
    @AppStorage(PreferenceKey.fingering) private var fingering = FingeringDisplay.all

    var body: some View {
        Form {
            Section {
                Picker("Noms des notes", selection: $naming) {
                    Text("Do Ré Mi Fa Sol La Si").tag(NoteNamingStyle.solfege)
                    Text("C D E F G A B").tag(NoteNamingStyle.letters)
                }
                Picker("Doigtés", selection: $fingering) {
                    Text("Masqués").tag(FingeringDisplay.off)
                    Text("Écrits seulement").tag(FingeringDisplay.written)
                    Text("Écrits et suggérés").tag(FingeringDisplay.all)
                }
                Picker("Visualisation par défaut", selection: $visualization) {
                    Text("Notes qui tombent").tag(Visualization.fallingNotes)
                    Text("Partition simplifiée").tag(Visualization.simplifiedSheet)
                    Text("Partition rythmique").tag(Visualization.rhythmicSheet)
                    Text("Partition complète").tag(Visualization.pageSheet)
                }
            }
            Section("Notes qui tombent") {
                Toggle("Afficher les noms des notes", isOn: $showsNoteNames)
                Toggle("Une couleur par note", isOn: $coloredNotes)
                Toggle("Clavier complet (88 touches)", isOn: $fullKeyboard)
                LabeledContent("Vitesse de défilement") {
                    Slider(value: $fallingSpeed, in: 100...450) {
                        Text("Vitesse de défilement")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                    .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PracticeSettingsView: View {
    @AppStorage(PreferenceKey.defaultMode) private var mode = PracticeMode.learn
    @AppStorage(PreferenceKey.waitTolerance) private var waitTolerance = 0.25
    @AppStorage(PreferenceKey.countdown) private var countdown = true
    @AppStorage(PreferenceKey.wrongNoteSound) private var wrongNoteSound = false
    @AppStorage(PreferenceKey.metronomeVolume) private var metronomeVolume = 0.6

    var body: some View {
        Form {
            Section {
                Picker("Mode par défaut", selection: $mode) {
                    Text("Apprendre").tag(PracticeMode.learn)
                    Text("Attendre").tag(PracticeMode.wait)
                    Text("Écouter").tag(PracticeMode.listen)
                }
                LabeledContent("Tolérance du mode Attendre") {
                    HStack {
                        Slider(value: $waitTolerance, in: PracticeSettings.waitToleranceRange, step: 0.05).labelsHidden()
                        Text("\(waitTolerance.formatted(.number.precision(.fractionLength(2)))) s")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Toggle("Décompte avant de jouer", isOn: $countdown)
                Toggle("Son des fausses notes", isOn: $wrongNoteSound)
                LabeledContent("Volume du métronome") {
                    Slider(value: $metronomeVolume, in: 0...1).labelsHidden()
                }
            } footer: {
                Text("Ces réglages s'appliquent aux morceaux que vous ouvrez pour la première fois. Chaque morceau garde ensuite ses propres réglages.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
