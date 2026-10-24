import MyPianoCore
import SwiftUI

/// Settings of a note-reading series, then a button opening it in a player window.
struct NoteReadingSetupView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("exercise.noteReading") private var stored = ""
    @State private var exercise = NoteReadingExercise()

    var body: some View {
        Form {
            Section {
                Text("Des notes isolées s'affichent sur la portée : jouez-les sur le clavier. La lecture attend chaque note.")
                    .foregroundStyle(.secondary)
            }
            Section("Série") {
                Picker("Portée", selection: $exercise.staff) {
                    Text("Clé de sol").tag(ExerciseStaff.treble)
                    Text("Clé de fa").tag(ExerciseStaff.bass)
                    Text("Les deux").tag(ExerciseStaff.grand)
                }
                KeyPicker(key: $exercise.key)
                Stepper(value: $exercise.noteCount, in: 8...64, step: 4) {
                    LabeledContent("Nombre de notes", value: "\(exercise.noteCount)")
                }
                Toggle("Lignes supplémentaires", isOn: $exercise.widerRange)
            }
            Section {
                Button {
                    openWindow(id: WindowID.player, value: PlayerTarget.noteReading(exercise, seed: .random(in: 1...UInt64.max)))
                } label: {
                    Label("Commencer", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lecture de notes")
        .onAppear { exercise = ExerciseStore.decode(stored) ?? exercise }
        .onChange(of: exercise) { stored = ExerciseStore.encode(exercise) }
    }
}

/// Settings of a generated phrase, then a button opening it in a player window.
struct PhraseSetupView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("exercise.phrase") private var stored = ""
    @State private var exercise = PhraseExercise()

    var body: some View {
        Form {
            Section {
                Text("De courtes pièces générées sur une suite d'accords, avec des rythmes de plus en plus riches.")
                    .foregroundStyle(.secondary)
            }
            Section("Phrase") {
                Picker("Niveau", selection: $exercise.level) {
                    Text("1 · Rondes et blanches").tag(0)
                    Text("2 · Noires").tag(1)
                    Text("3 · Croches").tag(2)
                    Text("4 · Rythmes pointés").tag(3)
                }
                Picker("Portée", selection: $exercise.staff) {
                    Text("Main droite seule").tag(ExerciseStaff.treble)
                    Text("Main gauche seule").tag(ExerciseStaff.bass)
                    Text("Deux mains").tag(ExerciseStaff.grand)
                }
                KeyPicker(key: $exercise.key)
                Stepper(value: $exercise.measures, in: 4...32, step: 4) {
                    LabeledContent("Mesures", value: "\(exercise.measures)")
                }
            }
            Section {
                Button {
                    openWindow(id: WindowID.player, value: PlayerTarget.phrase(exercise, seed: .random(in: 1...UInt64.max)))
                } label: {
                    Label("Commencer", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Phrases")
        .onAppear { exercise = ExerciseStore.decode(stored) ?? exercise }
        .onChange(of: exercise) { stored = ExerciseStore.encode(exercise) }
    }
}

/// Remembers the last exercise settings as JSON in the preferences.
enum ExerciseStore {
    static func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decode<T: Decodable>(_ string: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(string.utf8))
    }
}

/// Major keys from four flats to four sharps, named with the chosen note names.
struct KeyPicker: View {
    @Binding var key: KeySignature

    var body: some View {
        Picker("Tonalité", selection: $key) {
            ForEach(KeySignature.allCases.filter { abs($0.fifths) <= 4 }, id: \.self) { key in
                Text(KeyPicker.name(of: key)).tag(key)
            }
        }
    }

    static func name(of key: KeySignature) -> String {
        let tonic = key.tonic
        let accidental = tonic.alter > 0 ? "♯" : tonic.alter < 0 ? "♭" : ""
        let signature = key.fifths == 0 ? "" : " (\(abs(key.fifths))\(key.fifths > 0 ? "♯" : "♭"))"
        return String(localized: "\(Preferences.noteNaming.name(of: tonic.step))\(accidental) majeur\(signature)")
    }
}
