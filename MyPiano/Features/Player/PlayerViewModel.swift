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
    let subtitle: String?
    private(set) var settings: PracticeSettings
    private(set) var snapshot: PracticeSnapshot
    private(set) var display: DisplayOptions
    /// What the falling-notes view draws; rebuilt when settings or display options change.
    private(set) var scene: FallingNotesScene
    /// What the score view draws, when a score visualization is chosen.
    private(set) var sheetScene: SheetScene? = nil
    /// The quantized rhythms were too irregular: the simplified score is shown instead.
    private(set) var rhythmicFallback = false
    /// Shown when the song reaches its end.
    var finishedSummary: SessionSummary? = nil

    /// Called with the session summary when the session ends (window closed or song finished).
    @ObservationIgnored var onSessionEnded: ((SessionSummary) -> Void)?
    /// Called when practice settings change, to remember them for the song.
    @ObservationIgnored var onSettingsChanged: ((PracticeSettings) -> Void)?

    @ObservationIgnored let engine: PracticeEngine
    @ObservationIgnored private let input: PracticeInputRouter
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var playingSeconds: TimeInterval = 0
    @ObservationIgnored private var lastRefresh = Date()
    @ObservationIgnored private var furthestTime: TimeInterval = 0
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lastState: TransportCore.State = .paused
    @ObservationIgnored private var recorded = false

    init(song: Song, title: String, subtitle: String? = nil, settings: PracticeSettings, display: DisplayOptions,
         audio: PianoAudioEngine, input: PracticeInputRouter) {
        self.song = song
        self.title = title
        self.subtitle = subtitle
        self.input = input
        self.settings = settings
        self.display = display
        scene = Self.makeScene(song: song, settings: settings, display: display)
        engine = PracticeEngine(
            song: song,
            settings: settings,
            output: audio.songPiano,
            clickHandler: { sound, volume in audio.playClick(sound, gain: volume) }
        )
        snapshot = engine.snapshot()
        input.attach(engine)
        engine.startTimer()
        rebuildScenes()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Ends the session: reports it if it is worth keeping, then stops the engine.
    func close() {
        refreshTask?.cancel()
        refreshTask = nil
        reportSession()
        input.detach(engine)
        engine.shutdown()
        endActivity()
    }

    var isPlaying: Bool { snapshot.state == .playing || snapshot.state == .countingDown }

    var currentMeasureNumber: Int {
        song.measures.indices.contains(snapshot.measureIndex) ? song.measures[snapshot.measureIndex].number : 1
    }

    func togglePlayback() { engine.togglePlayback(); refresh() }

    func restart() {
        reportSession()
        engine.restart()
        sessionStart = nil
        playingSeconds = 0
        furthestTime = 0
        recorded = false
        refresh()
    }

    func previousMeasure() { engine.seekToPreviousMeasure(); refresh() }
    func nextMeasure() { engine.seekToNextMeasure(); refresh() }
    func seek(to time: TimeInterval) { engine.seek(to: time); refresh() }

    func update(_ change: (inout PracticeSettings) -> Void) {
        change(&settings)
        engine.update(settings: settings)
        rebuildScenes()
        refresh()
        onSettingsChanged?(settings)
    }

    func updateDisplay(_ change: (inout DisplayOptions) -> Void) {
        change(&display)
        rebuildScenes()
        Preferences.save(display)
    }

    func changeSpeed(by delta: Double) {
        update { $0.speed = PracticeSettings.clampedSpeed($0.speed + delta) }
    }

    func toggleHand(_ hand: Hand) {
        update { settings in
            if settings.hands.contains(hand) {
                if settings.hands.count > 1 { settings.hands.remove(hand) }
            } else {
                settings.hands.insert(hand)
            }
        }
    }

    /// Loops the current measure and the three after it, or removes the loop.
    func toggleLoop() {
        let first = snapshot.measureIndex
        let last = min(first + 3, max(0, song.measures.count - 1))
        update { $0.loop = $0.loop == nil ? LoopRange(firstMeasure: first, lastMeasure: last) : nil }
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

    // MARK: Session

    private func refresh() {
        let now = Date()
        snapshot = engine.snapshot()
        if isPlaying {
            if sessionStart == nil { sessionStart = now }
            playingSeconds += now.timeIntervalSince(lastRefresh)
            furthestTime = max(furthestTime, snapshot.time)
            beginActivity()
        } else {
            endActivity()
        }
        lastRefresh = now
        if snapshot.state == .finished && lastState != .finished {
            finishedSummary = makeSummary()
            reportSession()
        }
        lastState = snapshot.state
    }

    private func reportSession() {
        guard !recorded, let summary = makeSummary(), summary.isWorthRecording else { return }
        recorded = true
        onSessionEnded?(summary)
    }

    private func makeSummary() -> SessionSummary? {
        guard let sessionStart else { return nil }
        let span = settings.loop?.timeRange(in: song) ?? 0...max(song.duration, 0.001)
        let completion = (furthestTime - span.lowerBound) / max(0.001, span.upperBound - span.lowerBound)
        return SessionSummary(startedAt: sessionStart, practiceSeconds: playingSeconds, settings: settings,
                              stats: snapshot.stats, completion: snapshot.state == .finished ? 1 : completion)
    }

    /// Keeps the display awake while playing.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Practising a song"
        )
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    // MARK: Scenes

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
}
