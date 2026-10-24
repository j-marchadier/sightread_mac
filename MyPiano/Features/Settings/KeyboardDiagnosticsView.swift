import MyPianoAudio
import MyPianoCore
import MyPianoMIDI
import SwiftUI

/// The MIDI keyboard and sound settings: connection state, chosen inputs, live events,
/// volumes, test sounds and measured latency.
struct KeyboardDiagnosticsView: View {
    enum Part { case keyboard, audio }

    @Environment(AppModel.self) private var model
    let part: Part
    @AppStorage(PreferenceKey.computerKeyboardPiano) private var computerKeyboardPiano = false

    var body: some View {
        Form {
            switch part {
            case .keyboard:
                connectionSection
                computerKeyboardSection
                eventsSection
            case .audio:
                soundSection
                latencySection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section("Clavier MIDI") {
            LabeledContent("État") {
                switch model.midi.status {
                case .noKeyboard:
                    Label("Aucun clavier connecté", systemImage: "pianokeys")
                        .foregroundStyle(.secondary)
                case let .connected(names):
                    Label(names.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Toggle("Choisir l'entrée automatiquement", isOn: automaticBinding)
            if model.midi.sources.isEmpty {
                Text("Branchez un clavier MIDI : il sera détecté automatiquement.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.midi.sources) { source in
                Toggle(isOn: sourceBinding(source)) {
                    VStack(alignment: .leading) {
                        Text(source.name)
                        if let manufacturer = source.manufacturer {
                            Text(manufacturer).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isAutomatic || source.isOffline)
            }
            if let error = model.midi.errorDescription {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var eventsSection: some View {
        Section("Dernières notes") {
            if model.recentEvents.isEmpty {
                Text("Jouez quelques notes sur votre clavier.").foregroundStyle(.secondary)
            }
            ForEach(model.recentEvents) { record in
                HStack {
                    Text(description(of: record.event))
                    Spacer()
                    Text(record.receivedAt, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Pédale de sustain", value: model.isSustainDown ? String(localized: "enfoncée") : String(localized: "relâchée"))
        }
    }

    private var soundSection: some View {
        Section("Son") {
            LabeledContent("Moteur audio") {
                switch model.audioState {
                case .running: Text("En marche").foregroundStyle(.green)
                case .stopped: Text("Arrêté").foregroundStyle(.secondary)
                case let .failed(message): Text(message).foregroundStyle(.red)
                }
            }
            VolumeControls()
            HStack {
                Button("Jouer un Do") { playMiddleC() }
                Button("Clic") { model.audio.playClick(.beat) }
                Button("Accent") { model.audio.playClick(.accent) }
                Button("Erreur") { model.audio.playClick(.wrongNote) }
                Spacer()
                Button("Redémarrer l'audio") { model.restartAudio() }
            }
        }
    }

    private var computerKeyboardSection: some View {
        Section {
            Toggle("Jouer avec le clavier du Mac", isOn: $computerKeyboardPiano)
        } footer: {
            Text("Rangée du bas : Do3 à Si3 (touches noires sur la rangée du milieu). Rangée du haut : Do4 à Si4. Les flèches ↑ et ↓ changent d'octave (actuellement \(model.computerKeyboardOctave > 0 ? "+" : "")\(model.computerKeyboardOctave)).")
                .foregroundStyle(.secondary)
        }
    }

    private var latencySection: some View {
        Section("Latence") {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Sortie audio (estimée)", value: milliseconds(model.audio.estimatedOutputLatency))
                    if let summary = model.latency.summary() {
                        LabeledContent("Traitement d'une note (moyenne)", value: milliseconds(summary.average))
                        LabeledContent("Traitement d'une note (maximum)", value: milliseconds(summary.maximum))
                        LabeledContent("Total estimé", value: milliseconds(summary.average + model.audio.estimatedOutputLatency))
                    } else {
                        Text("Jouez une note pour mesurer la latence.").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var isAutomatic: Bool { model.midi.selection == .automatic }

    private var automaticBinding: Binding<Bool> {
        Binding(
            get: { isAutomatic },
            set: { automatic in
                model.midi.setSelection(automatic ? .automatic : .manual(Set(model.midi.connectedSources.map(\.id))))
            }
        )
    }

    private func sourceBinding(_ source: MIDISourceDescriptor) -> Binding<Bool> {
        Binding(
            get: { model.midi.connectedSources.contains { $0.id == source.id } },
            set: { isOn in
                guard case var .manual(ids) = model.midi.selection else { return }
                if isOn { ids.insert(source.id) } else { ids.remove(source.id) }
                model.midi.setSelection(.manual(ids))
            }
        )
    }

    private func description(of event: InputEvent) -> String {
        switch event.kind {
        case let .noteOn(pitch, velocity):
            String(localized: "\(noteName(pitch)) enfoncée (vélocité \(Int(velocity)))")
        case let .noteOff(pitch):
            String(localized: "\(noteName(pitch)) relâchée")
        case let .sustain(isDown):
            isDown ? String(localized: "Pédale enfoncée") : String(localized: "Pédale relâchée")
        }
    }

    private func noteName(_ pitch: UInt8) -> String {
        Preferences.noteNaming.name(of: Speller.spell(Int(pitch), in: nil), includeOctave: true)
    }

    private func milliseconds(_ seconds: TimeInterval) -> String {
        (seconds * 1000).formatted(.number.precision(.fractionLength(1))) + " ms"
    }

    private func playMiddleC() {
        let piano = model.audio.playerPiano
        piano.noteOn(60, velocity: 90)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            piano.noteOff(60)
        }
    }
}
