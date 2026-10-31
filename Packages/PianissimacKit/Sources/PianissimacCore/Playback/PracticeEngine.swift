import Dispatch
import Foundation

/// Runs a ``TransportCore`` in real time.
///
/// A high-priority timer advances the core about every millisecond; song notes go straight to the
/// `output` piano, clicks to `clickHandler`, and every event is also reported through `onEvents`
/// (on the engine's queue: hop to the main actor before touching UI state). All methods are
/// thread-safe; keyboard input can be fed from the MIDI thread with its hardware timestamp.
public final class PracticeEngine: @unchecked Sendable {
    public typealias Clock = @Sendable () -> TimeInterval

    private let lock = NSLock()
    private var core: TransportCore
    private let clock: Clock
    private let output: NoteOutput?
    private let clickHandler: (@Sendable (ClickSound, Float) -> Void)?
    private let onEvents: (@Sendable ([PracticeEvent]) -> Void)?
    private let queue = DispatchQueue(label: "fr.jmarchadier.Pianissimac.practice", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    public init(
        song: Song,
        settings: PracticeSettings,
        clock: @escaping Clock = { HostTime.now },
        output: NoteOutput?,
        clickHandler: (@Sendable (ClickSound, Float) -> Void)? = nil,
        onEvents: (@Sendable ([PracticeEvent]) -> Void)? = nil
    ) {
        core = TransportCore(song: song, settings: settings)
        self.clock = clock
        self.output = output
        self.clickHandler = clickHandler
        self.onEvents = onEvents
    }

    deinit {
        timer?.cancel()
    }

    public var song: Song { core.song }

    /// Starts the real-time timer. Without it, call ``tick()`` yourself (tests).
    public func startTimer(interval: DispatchTimeInterval = .milliseconds(1)) {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// Stops the timer and silences the song.
    public func shutdown() {
        lock.lock()
        timer?.cancel()
        timer = nil
        lock.unlock()
        perform { core, now in core.pause(at: now) }
        output?.allNotesOff()
    }

    public func tick() {
        perform { core, now in core.advance(to: now) }
    }

    public func play() { perform { core, now in core.play(at: now) } }
    public func pause() { perform { core, now in core.pause(at: now) } }
    public func togglePlayback() { perform { core, now in core.togglePlayback(at: now) } }
    public func restart() { perform { core, now in core.restart(at: now) } }

    public func seek(to time: TimeInterval) {
        perform { core, now in core.seek(to: time, at: now) }
    }

    public func seekToPreviousMeasure() {
        perform { core, now in core.seek(to: core.previousMeasureStart(from: core.time(at: now)), at: now) }
    }

    public func seekToNextMeasure() {
        perform { core, now in core.seek(to: core.nextMeasureStart(from: core.time(at: now)), at: now) }
    }

    public func update(settings: PracticeSettings) {
        perform { core, now in core.update(settings: settings, at: now) }
    }

    public func update(_ change: @Sendable (inout PracticeSettings) -> Void) {
        perform { core, now in
            var settings = core.settings
            change(&settings)
            return core.update(settings: settings, at: now)
        }
    }

    /// Feeds a keyboard event (judging only; the player's own sound is played elsewhere).
    public func handle(_ input: InputEvent) {
        switch input.kind {
        case let .noteOn(pitch, _):
            perform { core, _ in core.noteOn(pitch, at: input.time) }
        case let .noteOff(pitch):
            lock.lock()
            core.noteOff(pitch)
            lock.unlock()
        case .sustain:
            break
        }
    }

    public var settings: PracticeSettings {
        lock.lock()
        defer { lock.unlock() }
        return core.settings
    }

    public func snapshot() -> PracticeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return core.snapshot(at: clock())
    }

    /// Applies a change under the lock, then delivers its events outside it.
    private func perform(_ body: (inout TransportCore, TimeInterval) -> [PracticeEvent]) {
        lock.lock()
        let events = body(&core, clock())
        let settings = core.settings
        lock.unlock()
        deliver(events, settings: settings)
    }

    private func deliver(_ events: [PracticeEvent], settings: PracticeSettings) {
        guard !events.isEmpty else { return }
        for event in events {
            switch event {
            case let .noteStarted(_, pitch, velocity): output?.noteOn(pitch, velocity: velocity)
            case let .noteEnded(_, pitch): output?.noteOff(pitch)
            case let .sustain(isDown): output?.setSustain(isDown)
            case let .metronomeClick(accent): clickHandler?(accent ? .accent : .beat, settings.metronome.volume)
            case let .countdownBeat(remaining, total): clickHandler?(remaining == total ? .accent : .beat, settings.metronome.volume)
            case .wrongKey where settings.wrongNoteSound: clickHandler?(.wrongNote, 1)
            default: break
            }
        }
        onEvents?(events)
    }
}
