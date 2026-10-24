import Foundation
import MyPianoAudio
import MyPianoCore
import Observation

/// One open practice session: the real-time engine plus the state SwiftUI shows.
///
/// The engine runs on its own high-priority queue; this model refreshes a snapshot about 30 times
/// per second for the controls. Rendering views read `engine.snapshot()` themselves at frame rate.
@MainActor
@Observable
final class PlayerViewModel {
    let song: Song
    let title: String
    private(set) var settings: PracticeSettings
    private(set) var snapshot: PracticeSnapshot

    @ObservationIgnored let engine: PracticeEngine
    @ObservationIgnored private let input: PracticeInputRouter
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(song: Song, title: String, audio: PianoAudioEngine, input: PracticeInputRouter) {
        self.song = song
        self.title = title
        self.input = input
        let settings = PracticeSettings(handAssignment: HandAssigner.assign(song))
        self.settings = settings
        engine = PracticeEngine(
            song: song,
            settings: settings,
            output: audio.songPiano,
            clickHandler: { sound, volume in audio.playClick(sound, gain: volume) }
        )
        snapshot = engine.snapshot()
        input.attach(engine)
        engine.startTimer()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Stops the session. Call when the player view goes away.
    func close() {
        refreshTask?.cancel()
        refreshTask = nil
        input.detach(engine)
        engine.shutdown()
    }

    var isPlaying: Bool { snapshot.state == .playing || snapshot.state == .countingDown }

    func togglePlayback() { engine.togglePlayback(); refresh() }
    func restart() { engine.restart(); refresh() }
    func previousMeasure() { engine.seekToPreviousMeasure(); refresh() }
    func nextMeasure() { engine.seekToNextMeasure(); refresh() }
    func seek(to time: TimeInterval) { engine.seek(to: time); refresh() }

    func update(_ change: (inout PracticeSettings) -> Void) {
        change(&settings)
        engine.update(settings: settings)
        refresh()
    }

    private func refresh() {
        snapshot = engine.snapshot()
    }
}
