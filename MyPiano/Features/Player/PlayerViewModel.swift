import Foundation
import MyPianoAudio
import MyPianoCore
import MyPianoRendering
import Observation

/// How the song is displayed (independent of how it is practised).
struct DisplayOptions: Equatable {
    var fullKeyboard = true
    var showsNoteNames = false
    var naming: NoteNamingStyle = .solfege
    var pointsPerSecond: Double = 220
}

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
    private(set) var display = DisplayOptions()
    /// What the falling-notes view draws; rebuilt when settings or display options change.
    private(set) var scene: FallingNotesScene

    @ObservationIgnored let engine: PracticeEngine
    @ObservationIgnored private let input: PracticeInputRouter
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterScrub = false

    init(song: Song, title: String, audio: PianoAudioEngine, input: PracticeInputRouter) {
        self.song = song
        self.title = title
        self.input = input
        let settings = PracticeSettings(handAssignment: HandAssigner.assign(song))
        self.settings = settings
        scene = Self.makeScene(song: song, settings: settings, display: DisplayOptions())
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
        scene = Self.makeScene(song: song, settings: settings, display: display)
        refresh()
    }

    func updateDisplay(_ change: (inout DisplayOptions) -> Void) {
        change(&display)
        scene = Self.makeScene(song: song, settings: settings, display: display)
    }

    /// State of the current frame, for the renderers.
    func frame(pressedKeys: PressedKeys) -> FallingNotesFrame {
        let snapshot = engine.snapshot()
        return FallingNotesFrame(
            time: snapshot.time,
            hitNotes: snapshot.hitNotes,
            missedNotes: snapshot.missedNotes,
            pressedKeys: Set(pressedKeys.current.keys),
            loop: settings.loop?.timeRange(in: song)
        )
    }

    /// Moves through the song while the player drags or scrolls; playback resumes afterwards.
    func scrub(by seconds: TimeInterval) {
        if isPlaying {
            engine.pause()
            resumeAfterScrub = true
        }
        engine.seek(to: engine.snapshot().time + seconds)
    }

    func endScrub() {
        if resumeAfterScrub {
            resumeAfterScrub = false
            engine.play()
        }
        refresh()
    }

    private static func makeScene(song: Song, settings: PracticeSettings, display: DisplayOptions) -> FallingNotesScene {
        FallingNotesScene(
            song: song,
            noteHands: song.notes.map { settings.handAssignment.hand(for: $0) },
            activeHands: settings.mode == .listen ? [.left, .right] : settings.hands,
            labels: display.showsNoteNames ? NoteLabels.labels(for: song, transpose: settings.transpose, style: display.naming) : nil,
            keyNames: display.naming,
            transpose: settings.transpose,
            keyboardRange: KeyboardLayout.displayRange(for: song, transpose: settings.transpose, fullKeyboard: display.fullKeyboard),
            pointsPerSecond: display.pointsPerSecond
        )
    }

    private func refresh() {
        snapshot = engine.snapshot()
    }
}
