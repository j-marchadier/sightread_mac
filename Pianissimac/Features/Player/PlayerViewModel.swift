import Foundation
import PianissimacAudio
import PianissimacCore
import PianissimacRendering
import Observation

enum Visualization: String, CaseIterable {
    case fallingNotes
    case simplifiedSheet
    case rhythmicSheet
    /// The whole score in lines, like a printed page.
    case pageSheet

    var showsRhythms: Bool { self == .rhythmicSheet || self == .pageSheet }
}

/// Which fingers are shown on the notes.
enum FingeringDisplay: String, CaseIterable {
    case off
    /// Only the fingers written in the score.
    case written
    /// Written fingers, completed with Pianissimac's suggestions.
    case all
}

/// How the song is displayed (independent of how it is practised).
struct DisplayOptions: Equatable {
    var fingering: FingeringDisplay = .all
    var visualization: Visualization = .fallingNotes
    var coloredNotes = false
    var fullKeyboard = true
    var showsNoteNames = false
    var naming: NoteNamingStyle = .solfege
    var pointsPerSecond: Double = 220
}

/// One open practice session: the real-time engine plus the state SwiftUI shows.
///
/// The engine runs on its own high-priority queue; this model polls it about 30 times per second but
/// only publishes values that actually changed (playing state, measure, displayed second…), so views
/// are not rebuilt on every poll. Rendering views read `engine.snapshot()` themselves at frame rate.
@MainActor
@Observable
final class PlayerViewModel {
    let song: Song
    let title: String
    let subtitle: String?
    private(set) var settings: PracticeSettings
    /// The engine state at the last poll. Not observed: it changes on every poll.
    @ObservationIgnored private(set) var snapshot: PracticeSnapshot
    private(set) var isPlaying = false
    private(set) var measureIndex = 0
    /// Song position in whole seconds, for the time shown in the control bar.
    private(set) var displayedSecond = 0
    private(set) var isWaiting = false
    private(set) var countdownRemaining: Int?
    private(set) var stats = PracticeStats()
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
        publish(snapshot)
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

    var currentMeasureNumber: Int {
        song.measures.indices.contains(measureIndex) ? song.measures[measureIndex].number : 1
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
        publish(snapshot)
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

    /// Assigns only what changed: every assignment of an observed property rebuilds the views reading it.
    private func publish(_ snapshot: PracticeSnapshot) {
        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PlayerViewModel, Value>, _ value: Value) {
            if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
        }
        set(\.isPlaying, snapshot.state == .playing || snapshot.state == .countingDown)
        set(\.measureIndex, snapshot.measureIndex)
        set(\.displayedSecond, Int(snapshot.time))
        set(\.isWaiting, snapshot.isWaiting)
        set(\.countdownRemaining, snapshot.countdown?.remaining)
        set(\.stats, snapshot.stats)
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

    /// Fingers for the current hands and transposition, computed only when they change.
    @ObservationIgnored private var fingerCache: (key: FingerKey, fingers: [Finger?])?

    private struct FingerKey: Equatable {
        var hands: HandAssignment
        var transpose: Int
    }

    private func fingers(hands: [Hand?]) -> [Finger?]? {
        guard display.fingering == .all else {
            return Self.fingers(for: song, hands: hands, transpose: settings.transpose, display: display.fingering)
        }
        let key = FingerKey(hands: settings.handAssignment, transpose: settings.transpose)
        if let fingerCache, fingerCache.key == key { return fingerCache.fingers }
        let fingers = FingeringSuggester.fingers(for: song, hands: hands, transpose: settings.transpose)
        fingerCache = (key, fingers)
        return fingers
    }

    /// The fingers to show on each note (index = note id), or `nil` when fingers are hidden.
    static func fingers(for song: Song, hands: [Hand?], transpose: Int, display: FingeringDisplay) -> [Finger?]? {
        switch display {
        case .off:
            return nil
        case .written:
            return song.notes.map { note in
                guard let finger = note.finger, hands.indices.contains(note.id), hands[note.id] != nil else { return nil }
                return Finger(finger, isWritten: true)
            }
        case .all:
            return FingeringSuggester.fingers(for: song, hands: hands, transpose: transpose)
        }
    }

    /// The score of `song` in the given style; rhythms too irregular to quantize fall back to the simplified score.
    static func sheetStyle(for song: Song, hands: [Hand?], transpose: Int, rhythmic: Bool) -> (style: SheetScene.Style, isFallback: Bool) {
        guard rhythmic else { return (.simplified(SimplifiedScore(song: song, hands: hands, transpose: transpose)), false) }
        let score = RhythmicScore(song: song, hands: hands, transpose: transpose)
        if score.source == .quantized && score.quality < 0.6 {
            return (.simplified(SimplifiedScore(song: song, hands: hands, transpose: transpose)), true)
        }
        return (.rhythmic(score), false)
    }

    private func rebuildScenes() {
        scene = Self.makeScene(song: song, settings: settings, display: display)
        let noteHands = song.notes.map { settings.handAssignment.hand(for: $0) }
        let fingers = fingers(hands: noteHands)
        scene.fingers = fingers
        rhythmicFallback = false
        guard display.visualization != .fallingNotes else {
            sheetScene = nil
            return
        }
        let hands = song.notes.map { settings.handAssignment.hand(for: $0) }
        let (style, isFallback) = Self.sheetStyle(for: song, hands: hands, transpose: settings.transpose,
                                                  rhythmic: display.visualization.showsRhythms)
        rhythmicFallback = isFallback
        let keys = song.keySignatures.map { KeySignatureChange(tick: $0.tick, key: $0.key.transposed(by: settings.transpose)) }
        sheetScene = SheetScene(
            style: style, song: song, noteHands: hands,
            activeHands: settings.mode == .listen ? [.left, .right] : settings.hands,
            keys: keys, coloredNotes: display.coloredNotes,
            noteNames: display.showsNoteNames ? display.naming : nil,
            pointsPerSecond: display.pointsPerSecond * 0.75
        )
        sheetScene?.fingers = fingers
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
