import Foundation

/// Something the practice engine asks the outside world to do or to show.
public enum PracticeEvent: Sendable, Hashable {
    /// A song note starts sounding (already transposed). Silent notes produce no event.
    case noteStarted(id: Int, pitch: UInt8, velocity: UInt8)
    case noteEnded(id: Int, pitch: UInt8)
    /// Sustain pedal of the song.
    case sustain(isDown: Bool)
    case metronomeClick(accent: Bool)
    /// A count-in beat; `remaining` counts this beat (3, 2, 1 for a 3-beat count-in).
    case countdownBeat(remaining: Int, total: Int)
    case judged(noteID: Int, grade: Grade, offset: TimeInterval)
    case missed(noteID: Int)
    case wrongKey(pitch: UInt8)
    case loopRestarted
    case finished
}

/// Read-only state for display.
public struct PracticeSnapshot: Sendable, Equatable {
    public var state: TransportCore.State
    /// Position in the song, in seconds at 100 % speed.
    public var time: TimeInterval
    public var isWaiting: Bool
    public var countdown: (remaining: Int, total: Int)?
    public var stats: PracticeStats
    public var hitNotes: Set<Int>
    public var missedNotes: Set<Int>
    public var measureIndex: Int

    public static func == (lhs: PracticeSnapshot, rhs: PracticeSnapshot) -> Bool {
        lhs.state == rhs.state && lhs.time == rhs.time && lhs.isWaiting == rhs.isWaiting
            && lhs.countdown?.remaining == rhs.countdown?.remaining && lhs.countdown?.total == rhs.countdown?.total
            && lhs.stats == rhs.stats && lhs.hitNotes == rhs.hitNotes && lhs.missedNotes == rhs.missedNotes
            && lhs.measureIndex == rhs.measureIndex
    }
}

/// The practice engine's logic: transport, wait mode, loop, count-in, metronome and judging.
///
/// It is a pure value type driven by host times supplied by the caller (`advance(to:)` about every
/// millisecond, `noteOn(_:at:)` with the key's hardware timestamp), so it is deterministic and
/// fully testable. Song positions are seconds at 100 % speed; judging windows are real seconds.
public struct TransportCore: Sendable {
    public enum State: Sendable, Equatable {
        case paused
        case countingDown
        case playing
        case finished
    }

    public let song: Song
    public private(set) var settings: PracticeSettings
    public private(set) var state: State = .paused
    public private(set) var stats = PracticeStats()
    public private(set) var hitNotes: Set<Int> = []
    public private(set) var missedNotes: Set<Int> = []

    private var position: TimeInterval = 0
    private var anchorHost: TimeInterval = 0
    private var anchorSong: TimeInterval = 0
    private var nextNote = 0
    private var nextSustain = 0
    private var sounding: [Int: UInt8] = [:]
    private var pendingLate: [Int] = []
    private var pressedKeys: [UInt8: Int?] = [:] // key → note it correctly played
    private var waitingAt: TimeInterval?
    private var lastClickTick: Double = -1
    private var countdown: Countdown?
    private var noteHands: [Hand?]

    private struct Countdown: Sendable {
        var startHost: TimeInterval
        var interval: TimeInterval
        var total: Int
        var emitted: Int
    }

    public init(song: Song, settings: PracticeSettings = PracticeSettings()) {
        self.song = song
        self.settings = settings
        noteHands = song.notes.map { settings.handAssignment.hand(for: $0) }
        if let start = loopTimes?.start {
            _ = seek(to: start, at: 0)
        }
    }

    // MARK: Queries

    /// Song position at a host time (interpolated while playing, never past a note the wait mode holds).
    public func time(at host: TimeInterval) -> TimeInterval {
        guard state == .playing else { return position }
        let time = max(0, anchorSong + (host - anchorHost) * settings.speed)
        if let waitingAt { return min(time, waitingAt) }
        return time
    }

    public func snapshot(at host: TimeInterval) -> PracticeSnapshot {
        let time = time(at: host)
        var countdownState: (Int, Int)?
        if let countdown, state == .countingDown {
            countdownState = (max(1, countdown.total - countdown.emitted + 1), countdown.total)
        }
        return PracticeSnapshot(
            state: state, time: time, isWaiting: waitingAt != nil && state == .playing,
            countdown: countdownState, stats: stats, hitNotes: hitNotes, missedNotes: missedNotes,
            measureIndex: song.measureIndex(at: time)
        )
    }

    public var loopTimes: (start: TimeInterval, end: TimeInterval)? {
        guard let range = settings.loop?.timeRange(in: song) else { return nil }
        return (range.lowerBound, range.upperBound)
    }

    /// Whether the note belongs to a hand being practised.
    public func isActive(_ note: Note) -> Bool {
        guard settings.mode != .listen, let hand = noteHands[note.id] else { return false }
        return settings.hands.contains(hand)
    }

    public func hand(of note: Note) -> Hand? { noteHands[note.id] }

    public func outputPitch(of note: Note) -> UInt8 {
        PianoKeys.transpose(note.pitch, by: settings.transpose)
    }

    // MARK: Transport

    public mutating func play(at host: TimeInterval) -> [PracticeEvent] {
        switch state {
        case .playing, .countingDown:
            return []
        case .finished:
            var events = seek(to: loopTimes?.start ?? 0, at: host)
            events += startPlaying(at: host)
            return events
        case .paused:
            if position >= song.duration && loopTimes == nil {
                var events = seek(to: 0, at: host)
                events += startPlaying(at: host)
                return events
            }
            return startPlaying(at: host)
        }
    }

    public mutating func pause(at host: TimeInterval) -> [PracticeEvent] {
        guard state == .playing || state == .countingDown else { return [] }
        var events = state == .playing ? advance(to: host) : []
        if state == .playing || state == .countingDown { state = .paused }
        countdown = nil
        waitingAt = nil
        events += silence()
        return events
    }

    public mutating func togglePlayback(at host: TimeInterval) -> [PracticeEvent] {
        state == .playing || state == .countingDown ? pause(at: host) : play(at: host)
    }

    /// Moves to `time` (clamped to the song, or to the loop). Judged notes after it can be played again.
    public mutating func seek(to time: TimeInterval, at host: TimeInterval) -> [PracticeEvent] {
        var target = min(max(0, time), song.duration)
        if let loop = loopTimes { target = min(max(target, loop.start), loop.end) }
        let events = silence()
        position = target
        anchorSong = target
        anchorHost = host
        waitingAt = nil
        nextNote = firstNoteIndex(startingAtOrAfter: target)
        nextSustain = song.sustainChanges.firstIndex { $0.time >= target } ?? song.sustainChanges.count
        pendingLate.removeAll()
        hitNotes = hitNotes.filter { song.notes[$0].start < target }
        missedNotes = missedNotes.filter { song.notes[$0].start < target }
        lastClickTick = Double(song.tempoMap.tick(atSeconds: target)) - 0.5
        if state == .finished { state = .paused }
        return events
    }

    /// Back to the start (of the loop, if any) with fresh statistics.
    public mutating func restart(at host: TimeInterval) -> [PracticeEvent] {
        var events = pause(at: host)
        events += seek(to: loopTimes?.start ?? 0, at: host)
        stats = PracticeStats()
        hitNotes.removeAll()
        missedNotes.removeAll()
        return events
    }

    public mutating func update(settings newSettings: PracticeSettings, at host: TimeInterval) -> [PracticeEvent] {
        var events: [PracticeEvent] = []
        if state == .playing {
            anchorSong = time(at: host)
            anchorHost = host
        }
        let old = settings
        settings = newSettings
        if old.handAssignment != newSettings.handAssignment {
            noteHands = song.notes.map { newSettings.handAssignment.hand(for: $0) }
        }
        if old.transpose != newSettings.transpose || old.mutedTracks != newSettings.mutedTracks || old.muteMyPart != newSettings.muteMyPart {
            events += silence()
        }
        if old.mode != newSettings.mode || old.hands != newSettings.hands {
            pendingLate.removeAll()
            waitingAt = nil
        }
        if let loop = loopTimes, position < loop.start - 0.0005 || position > loop.end {
            events += seek(to: loop.start, at: host)
        }
        if let countdown, old.speed != newSettings.speed {
            self.countdown?.interval = countdown.interval * old.speed / newSettings.speed
        }
        return events
    }

    // MARK: Measures

    /// Start of the current measure, or of the previous one when already at a measure start.
    public func previousMeasureStart(from time: TimeInterval) -> TimeInterval {
        guard !song.measures.isEmpty else { return 0 }
        let index = song.measureIndex(at: time)
        if time - song.measures[index].start > 0.05 { return song.measures[index].start }
        return song.measures[max(0, index - 1)].start
    }

    public func nextMeasureStart(from time: TimeInterval) -> TimeInterval {
        guard !song.measures.isEmpty else { return song.duration }
        let index = song.measureIndex(at: time)
        return index + 1 < song.measures.count ? song.measures[index + 1].start : song.duration
    }

    // MARK: Time

    public mutating func advance(to host: TimeInterval) -> [PracticeEvent] {
        var events: [PracticeEvent] = []
        if state == .countingDown {
            events += advanceCountdown(to: host)
        }
        guard state == .playing else { return events }

        var target = max(position, anchorSong + (host - anchorHost) * settings.speed)
        if settings.mode == .wait, let blocking = firstBlockingNoteStart(before: target) {
            target = blocking
            anchorSong = blocking
            anchorHost = host
            waitingAt = blocking
        } else {
            waitingAt = nil
        }

        if let loop = loopTimes, target >= loop.end, position < loop.end {
            events += process(to: loop.end)
            events += seek(to: loop.start, at: host)
            events.append(.loopRestarted)
            if settings.countdownEnabled {
                events += startCountdown(at: host)
            }
            return events
        }
        if loopTimes == nil, target >= song.duration {
            events += process(to: song.duration)
            position = song.duration
            state = .finished
            waitingAt = nil
            events += silence()
            events.append(.finished)
            return events
        }
        events += process(to: target)
        return events
    }

    private mutating func process(to target: TimeInterval) -> [PracticeEvent] {
        var events: [PracticeEvent] = []
        let previous = position
        guard target >= previous else { return events }

        // Notes that finish.
        for (id, pitch) in sounding where song.notes[id].end <= target {
            events.append(.noteEnded(id: id, pitch: pitch))
            sounding[id] = nil
        }
        // Song pedal.
        while nextSustain < song.sustainChanges.count, song.sustainChanges[nextSustain].time < target {
            let change = song.sustainChanges[nextSustain]
            if !settings.mutedTracks.contains(change.track) { events.append(.sustain(isDown: change.isDown)) }
            nextSustain += 1
        }
        // Notes that start.
        while nextNote < song.notes.count, song.notes[nextNote].start < target {
            let note = song.notes[nextNote]
            let active = isActive(note)
            if active && settings.mode != .listen && !hitNotes.contains(note.id) {
                pendingLate.append(note.id)
            }
            if isAudible(note, active: active) {
                let pitch = outputPitch(of: note)
                sounding[note.id] = pitch
                events.append(.noteStarted(id: note.id, pitch: pitch, velocity: note.velocity))
            }
            nextNote += 1
        }
        // Notes not played in time (the wait mode waits instead).
        if settings.mode == .learn { pendingLate.removeAll { id in
            let late = (target - song.notes[id].start) / settings.speed
            guard late > settings.windows.good else { return false }
            missedNotes.insert(id)
            stats.recordMiss()
            events.append(.missed(noteID: id))
            return true
        } }
        // Metronome.
        if settings.metronome.isEnabled {
            events += metronomeClicks(upTo: target)
        }
        // Correct notes still held.
        let held = pressedKeys.values.compactMap { $0 }.filter { id in
            let note = song.notes[id]
            return note.start <= target && target < note.end
        }.count
        if held > 0 {
            stats.heldSeconds += (target - previous) / settings.speed * Double(held)
        }
        position = target
        return events
    }

    // MARK: Input

    public mutating func noteOn(_ pitch: UInt8, at host: TimeInterval) -> [PracticeEvent] {
        guard state == .playing, settings.mode != .listen else {
            pressedKeys[pitch] = .some(nil)
            return []
        }
        let now = time(at: host)
        let window = settings.windows.good
        var best: (id: Int, offset: TimeInterval)?

        let waiting = settings.mode == .wait
        func consider(_ id: Int) {
            let note = song.notes[id]
            guard outputPitch(of: note) == pitch, !hitNotes.contains(id) else { return }
            var offset = (now - note.start) / settings.speed
            if waiting && offset > 0 {
                // The song waits for this note: lateness only counts beyond the tolerance.
                offset = max(0, offset - settings.waitTolerance)
            } else if abs(offset) > window {
                return
            }
            if best == nil || abs(offset) < abs(best!.offset) { best = (id, offset) }
        }
        for id in pendingLate { consider(id) }
        var index = nextNote
        while index < song.notes.count, (song.notes[index].start - now) / settings.speed <= window {
            if isActive(song.notes[index]) { consider(index) }
            index += 1
        }

        guard let best else {
            pressedKeys[pitch] = .some(nil)
            stats.recordWrongKey()
            return [.wrongKey(pitch: pitch)]
        }
        let grade: Grade = abs(best.offset) <= settings.windows.perfect ? .perfect : .good
        hitNotes.insert(best.id)
        pendingLate.removeAll { $0 == best.id }
        pressedKeys[pitch] = best.id
        stats.recordHit(grade)
        var events: [PracticeEvent] = [.judged(noteID: best.id, grade: grade, offset: best.offset)]
        // In wait mode a note reached before being played was kept silent: let it sound now.
        let note = song.notes[best.id]
        if waiting && note.start < position && sounding[note.id] == nil && note.end > position && isAudible(note, active: true) {
            let output = outputPitch(of: note)
            sounding[note.id] = output
            events.append(.noteStarted(id: note.id, pitch: output, velocity: note.velocity))
        }
        return events
    }

    public mutating func noteOff(_ pitch: UInt8) {
        pressedKeys[pitch] = nil
    }

    // MARK: Helpers

    private func isAudible(_ note: Note, active: Bool) -> Bool {
        if settings.mutedTracks.contains(note.track) { return false }
        let unplayed = active && !hitNotes.contains(note.id)
        if unplayed && (settings.muteMyPart || settings.mode == .wait) { return false }
        return true
    }

    /// In wait mode, where the song must stop: the start of the earliest active note not yet
    /// played, plus the tolerance during which it may still be played without stopping.
    private func firstBlockingNoteStart(before target: TimeInterval) -> TimeInterval? {
        var earliest = pendingLate.map { song.notes[$0].start }.min()
        var index = nextNote
        while index < song.notes.count, song.notes[index].start < target, earliest == nil {
            let note = song.notes[index]
            if isActive(note) && !hitNotes.contains(note.id) { earliest = note.start }
            index += 1
        }
        guard let earliest else { return nil }
        let stop = earliest + settings.waitTolerance * settings.speed
        return stop < target ? max(position, stop) : nil
    }

    private func firstNoteIndex(startingAtOrAfter time: TimeInterval) -> Int {
        var low = 0
        var high = song.notes.count
        while low < high {
            let mid = (low + high) / 2
            if song.notes[mid].start < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private mutating func silence() -> [PracticeEvent] {
        let events = sounding.sorted { $0.key < $1.key }.map { PracticeEvent.noteEnded(id: $0.key, pitch: $0.value) }
        sounding.removeAll()
        return events
    }

    private mutating func startPlaying(at host: TimeInterval) -> [PracticeEvent] {
        let atLoopStart = loopTimes.map { abs(position - $0.start) < 0.0005 } ?? false
        if settings.countdownEnabled && (position <= 0.0005 || atLoopStart) {
            return startCountdown(at: host)
        }
        state = .playing
        anchorHost = host
        anchorSong = position
        return []
    }

    private mutating func startCountdown(at host: TimeInterval) -> [PracticeEvent] {
        // A pickup measure (much shorter than the next) counts in with the next measure's meter.
        var reference = position
        let index = song.measureIndex(at: position)
        if index + 1 < song.measures.count, song.measures[index].duration < song.measures[index + 1].duration * 0.75 {
            reference = song.measures[index + 1].start
        }
        let tick = song.tempoMap.tick(atSeconds: reference)
        let signature = song.timeSignature(atTick: tick)
        let bpm = max(1, song.tempoMap.bpm(atTick: tick) * settings.speed)
        let interval = 60 / bpm * 4 / Double(signature.denominator)
        state = .countingDown
        countdown = Countdown(startHost: host, interval: interval, total: max(1, signature.numerator), emitted: 0)
        return advanceCountdown(to: host)
    }

    private mutating func advanceCountdown(to host: TimeInterval) -> [PracticeEvent] {
        guard var countdown else { return [] }
        var events: [PracticeEvent] = []
        while countdown.emitted < countdown.total, host >= countdown.startHost + Double(countdown.emitted) * countdown.interval {
            events.append(.countdownBeat(remaining: countdown.total - countdown.emitted, total: countdown.total))
            countdown.emitted += 1
        }
        let end = countdown.startHost + Double(countdown.total) * countdown.interval
        if host >= end {
            self.countdown = nil
            state = .playing
            anchorHost = end
            anchorSong = position
        } else {
            self.countdown = countdown
        }
        return events
    }

    /// Clicks on the beats (or subdivisions) crossed up to `target`, accenting measure starts.
    private mutating func metronomeClicks(upTo target: TimeInterval) -> [PracticeEvent] {
        let targetTick = Double(song.tempoMap.tick(atSeconds: target))
        guard targetTick > lastClickTick, !song.measures.isEmpty else { return [] }
        var events: [PracticeEvent] = []
        var index = song.measureIndex(atTick: Int(max(0, lastClickTick)))
        let ppq = song.ticksPerQuarter
        while index < song.measures.count, Double(song.measures[index].startTick) <= targetTick {
            let measure = song.measures[index]
            let signature = song.timeSignature(atTick: measure.startTick)
            let step = Double(signature.ticksPerBeat(ticksPerQuarter: ppq)) / settings.metronome.clicksPerBeat
            var position = Double(measure.startTick)
            var beat = 0
            while position < Double(measure.endTick) - 0.5 {
                if position > lastClickTick && position <= targetTick {
                    events.append(.metronomeClick(accent: beat == 0 && settings.metronome.accentsFirstBeat))
                }
                beat += 1
                position = Double(measure.startTick) + Double(beat) * step
            }
            index += 1
        }
        lastClickTick = targetTick
        return events
    }
}
