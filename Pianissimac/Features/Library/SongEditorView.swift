import AppKit
import PianissimacCore
import SwiftUI

/// Edits a song's title, composer, difficulty and which tracks each hand plays.
struct SongEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let songID: String

    @State private var song: Song?
    @State private var title = ""
    @State private var composer = ""
    @State private var difficulty = 1
    @State private var settings = PracticeSettings()
    @State private var newArtwork: NSImage?
    @State private var resetsArtwork = false
    @State private var isPickingArtwork = false
    @State private var artworkError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Pochette") {
                    HStack(spacing: 16) {
                        artworkPreview
                            .frame(width: 96, height: 96)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Choisir une image…") { isPickingArtwork = true }
                            Button("Utiliser la pochette générée") {
                                newArtwork = nil
                                resetsArtwork = true
                            }
                            .disabled(!hasCustomArtwork)
                            if let artworkError {
                                Text(artworkError).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                Section("Morceau") {
                    TextField("Titre", text: $title)
                    TextField("Compositeur", text: $composer)
                    LabeledContent("Difficulté") {
                        HStack {
                            Picker("Difficulté", selection: $difficulty) {
                                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                            if let song {
                                Button("Estimer") { difficulty = DifficultyEstimator.rating(for: song) }
                                    .help("Estimer la difficulté d'après les notes")
                            }
                        }
                    }
                }
                if let song {
                    Section {
                        ForEach(song.tracks.indices, id: \.self) { index in
                            TrackHandRow(song: song, index: index, assignment: $settings.handAssignment)
                        }
                        HandPreview(song: song, assignment: settings.handAssignment)
                            .frame(height: 150)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    } header: {
                        HStack {
                            Text("Mains")
                            Spacer()
                            Button("Détecter automatiquement") { settings.handAssignment = HandAssigner.assign(song) }
                                .controlSize(.small)
                        }
                    } footer: {
                        Text("Les pistes en accompagnement sont jouées par Pianissimac et ne sont pas évaluées.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 720)
        .task { load() }
        .fileImporter(isPresented: $isPickingArtwork, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let image = NSImage(contentsOf: url) {
                newArtwork = image
                resetsArtwork = false
                artworkError = nil
            } else {
                artworkError = String(localized: "Cette image ne peut pas être lue.")
            }
        }
    }

    private var hasCustomArtwork: Bool {
        newArtwork != nil || (!resetsArtwork && model.library.artwork.image(for: songID) != nil)
    }

    /// The cover as it will be once saved.
    @ViewBuilder
    private var artworkPreview: some View {
        if let newArtwork {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay { Image(nsImage: newArtwork).resizable().scaledToFill() }
                .clipShape(.rect(cornerRadius: 8))
        } else if !resetsArtwork, let image = model.library.artwork.image(for: songID) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay { Image(nsImage: image).resizable().scaledToFill() }
                .clipShape(.rect(cornerRadius: 8))
        } else {
            GeneratedArtwork(title: title, composer: composer.isEmpty ? nil : composer)
                .clipShape(.rect(cornerRadius: 8))
        }
    }

    private func load() {
        guard let entry = model.library.database.song(songID) else { return }
        title = entry.title
        composer = entry.composer ?? ""
        difficulty = entry.difficulty
        song = try? model.library.song(for: songID)
        if let song {
            settings = entry.settings ?? Preferences.newSongSettings(handAssignment: HandAssigner.assign(song))
        }
    }

    private func save() {
        let composer = composer.trimmingCharacters(in: .whitespaces)
        model.library.updateDetails(songID, title: title.trimmingCharacters(in: .whitespaces),
                                    composer: composer.isEmpty ? nil : composer, difficulty: difficulty)
        if song != nil { model.library.saveSettings(settings, for: songID) }
        if let newArtwork {
            do {
                try model.library.artwork.setImage(newArtwork, for: songID)
            } catch {
                artworkError = String(localized: "La pochette n'a pas pu être enregistrée.")
                return
            }
        } else if resetsArtwork {
            model.library.artwork.removeImage(for: songID)
        }
        dismiss()
    }
}

/// The role of one track: a hand, both hands split at a key, or accompaniment.
private struct TrackHandRow: View {
    enum Role: Hashable { case left, right, split, accompaniment }

    let song: Song
    let index: Int
    @Binding var assignment: HandAssignment

    var body: some View {
        let track = song.tracks[index]
        let count = song.notes.filter { $0.track == index }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text(track.name ?? String(localized: "Piste \(index + 1)"))
                    Text("\(count) notes").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Rôle", selection: role) {
                    Text("Main gauche").tag(Role.left)
                    Text("Main droite").tag(Role.right)
                    Text("Les deux mains").tag(Role.split)
                    Text("Accompagnement").tag(Role.accompaniment)
                }
                .labelsHidden()
                .fixedSize()
            }
            if let split = assignment.splitTracks[index] {
                Stepper(value: Binding(get: { Int(split) }, set: { assignment.splitTracks[index] = UInt8(clamping: $0) }), in: 36...84) {
                    LabeledContent("Main droite à partir de", value: noteName(split))
                }
            }
        }
    }

    private var role: Binding<Role> {
        Binding(get: {
            if assignment.splitTracks[index] != nil { return .split }
            if assignment.leftTracks.contains(index) { return .left }
            if assignment.rightTracks.contains(index) { return .right }
            return .accompaniment
        }, set: { role in
            assignment.leftTracks.remove(index)
            assignment.rightTracks.remove(index)
            assignment.splitTracks[index] = nil
            switch role {
            case .left: assignment.leftTracks.insert(index)
            case .right: assignment.rightTracks.insert(index)
            case .split: assignment.splitTracks[index] = 60
            case .accompaniment: break
            }
        })
    }

    private func noteName(_ pitch: UInt8) -> String {
        Preferences.noteNaming.name(of: Speller.spell(Int(pitch), in: nil), includeOctave: true)
    }
}

/// The first seconds of the song as a piano roll, coloured by hand.
private struct HandPreview: View {
    let song: Song
    let assignment: HandAssignment

    var body: some View {
        Canvas { context, size in
            let notes = song.notes
            guard let low = notes.map(\.pitch).min(), let high = notes.map(\.pitch).max() else { return }
            let span = min(song.duration, 30)
            let rows = CGFloat(max(12, Int(high) - Int(low) + 3))
            let rowHeight = size.height / rows
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(.secondary.opacity(0.08)))
            for note in notes where note.start < span {
                let x = CGFloat(note.start / span) * size.width
                let width = max(2, CGFloat(note.duration / span) * size.width - 1)
                let y = size.height - CGFloat(Int(note.pitch) - Int(low) + 2) * rowHeight
                let color: Color = switch assignment.hand(for: note) {
                case .left: .orange
                case .right: .blue
                case nil: .gray.opacity(0.5)
                }
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: max(2, rowHeight - 1)), cornerRadius: 1.5),
                             with: .color(color))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                Label("Main gauche", systemImage: "circle.fill").foregroundStyle(.orange)
                Label("Main droite", systemImage: "circle.fill").foregroundStyle(.blue)
            }
            .font(.caption2)
            .padding(6)
        }
        .accessibilityLabel(Text("Aperçu des mains"))
    }
}
