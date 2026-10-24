import Foundation
import MyPianoAudio
import MyPianoCore
import MyPianoRendering
import Observation

enum Visualization: String, CaseIterable {
    case fallingNotes
    case simplifiedSheet
    case rhythmicSheet
}

/// How the song is displayed (independent of how it is practised).
struct DisplayOptions: Equatable {
    var visualization: Visualization = .fallingNotes
    var coloredNotes = false
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
    /// What the score view draws, when a score visualization is chosen.
    private(set) var sheetScene: SheetScene? = nil
    /// The quantized rhythms were too irregular: the simplified score is shown instead.
    private(set) var rhythmicFallback = false

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
        rebuildScenes()
        refresh()
    }

    func updateDisplay(_ change: (inout DisplayOptions) -> Void) {
        change(&display)
        rebuildScenes()
    }

    private func rebuildScenes() {
        scene = Self.makeScene(song: song, settings: settings, display: display)
        rhythmicFallback = false
        guard display.visualization != .fallingNotes else {
            sheetScene = nil
            return
        }
        let hands = song.notes.map { settings.handAssignment.hand(for: $0) }
        let style: SheetScene.Style
        if display.visualization == .rhythmicSheet {
            let rhythmic = RhythmicScore(song: song, hands: hands, transpose: settings.transpose)
            if rhythmic.source == .quantized && rhythmic.quality < 0.6 {
                rhythmicFallback = true
                style = .simplified(SimplifiedScore(song: song, hands: hands, transpose: settings.transpose))
            } else {
                style = .rhythmic(rhythmic)
            }
        } else {
            style = .simplified(SimplifiedScore(song: song, hands: hands, transpose: settings.transpose))
        }
        let keys = song.keySignatures.map { KeySignatureChange(tick: $0.tick, key: $0.key.transposed(by: settings.transpose)) }
        sheetScene = SheetScene(
            style: style, song: song, noteHands: hands,
            activeHands: settings.mode == .listen ? [.left, .right] : settings.hands,
            keys: keys, coloredNotes: display.coloredNotes,
            noteNames: display.showsNoteNames ? display.naming : nil,
            pointsPerSecond: display.pointsPerSecond * 0.75
        )
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
