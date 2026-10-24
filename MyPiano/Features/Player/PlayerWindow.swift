import MyPianoCore
import SwiftUI

/// Root of a player window: loads the song or exercise, then shows the player.
struct PlayerWindow: View {
    @Environment(AppModel.self) private var model
    @State private var target: PlayerTarget
    @State private var player: PlayerViewModel?
    @State private var loadError: String?

    init(target: PlayerTarget) {
        _target = State(initialValue: target)
    }

    var body: some View {
        Group {
            if let player {
                PlayerView(player: player, isExercise: target.isExercise, onNewExercise: newExercise)
                    .id(ObjectIdentifier(player))
            } else if let loadError {
                ContentUnavailableView {
                    Label("Impossible d'ouvrir le morceau", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .task {
            model.start()
            if player == nil { open(target) }
        }
        .onDisappear {
            player?.close()
            player = nil
        }
    }

    private func newExercise() {
        target = target.regenerated()
        open(target)
    }

    private func open(_ target: PlayerTarget) {
        player?.close()
        player = nil
        do {
            let library = model.library
            let song: Song
            let title: String
            var subtitle: String?
            var settings: PracticeSettings
            var display = Preferences.display
            switch target {
            case let .song(id):
                guard let entry = library.database.song(id) else { throw CocoaError(.fileNoSuchFile) }
                song = try library.song(for: id)
                title = entry.title
                subtitle = entry.composer
                settings = entry.settings ?? Preferences.newSongSettings(handAssignment: HandAssigner.assign(song))
            case let .noteReading(exercise, seed):
                song = exercise.makeSong(seed: seed)
                title = String(localized: "Lecture de notes")
                settings = Preferences.newSongSettings(handAssignment: HandAssignment(leftTracks: [1], rightTracks: [0]))
                settings.mode = .wait
                settings.countdownEnabled = false
                display.visualization = .simplifiedSheet
            case let .phrase(exercise, seed):
                song = exercise.makeSong(seed: seed)
                title = String(localized: "Phrases")
                subtitle = String(localized: "Niveau \(exercise.level + 1)")
                settings = Preferences.newSongSettings(handAssignment: HandAssignment(leftTracks: [1], rightTracks: [0]))
                display.visualization = .rhythmicSheet
            }
            let player = PlayerViewModel(song: song, title: title, subtitle: subtitle, settings: settings, display: display,
                                         audio: model.audio, input: model.practiceInput)
            if case let .song(id) = target {
                player.onSettingsChanged = { [weak library] settings in library?.saveSettings(settings, for: id) }
                player.onSessionEnded = { [weak library] summary in library?.record(summary, for: id) }
            }
            self.player = player
            loadError = nil
        } catch let error as SongLoadingError {
            loadError = LibraryModel.describe(error)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
