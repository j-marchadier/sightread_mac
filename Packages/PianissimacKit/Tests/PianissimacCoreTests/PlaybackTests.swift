import Foundation
import Testing
@testable import PianissimacCore

private typealias N = TestSongs.N

@Suite("Transport")
struct TransportTests {
    let song = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 62, beat: 1), N(pitch: 64, beat: 2)])

    @Test func playsNotesInOrderAndFinishes() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(0.4)
        #expect(abs(driver.time - 0.4) < 1e-6)
        #expect(driver.started() == [0])
        driver.run(0.2)
        #expect(driver.started() == [0, 1])
        #expect(driver.log.contains(.noteEnded(id: 0, pitch: 60)))
        driver.run(1.5)
        #expect(driver.core.state == .finished)
        #expect(driver.time == song.duration)
        #expect(driver.log.last == .finished)
        #expect(driver.count { if case .noteEnded = $0 { true } else { false } } == 3)
    }

    @Test func speedScalesSongTime() {
        var driver = CoreDriver(song, TestSongs.settings { $0.speed = 0.5 })
        driver.play()
        driver.run(1.0)
        #expect(abs(driver.time - 0.5) < 1e-6)
    }

    @Test func pauseKeepsThePosition() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(0.3)
        driver.pause()
        driver.now += 5
        #expect(abs(driver.time - 0.3) < 1e-6)
        driver.play()
        driver.run(0.1)
        #expect(abs(driver.time - 0.4) < 1e-6)
    }

    @Test func playingAgainAfterTheEndRestarts() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(2)
        driver.play()
        driver.run(0.1)
        #expect(driver.core.state == .playing)
        #expect(abs(driver.time - 0.1) < 1e-6)
    }

    @Test func seekingClearsLaterJudgementsButKeepsStatistics() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(0.01)
        driver.press(60)
        #expect(driver.core.hitNotes == [0])
        _ = driver.core.seek(to: 0, at: driver.now)
        #expect(driver.core.hitNotes.isEmpty)
        #expect(driver.core.stats.perfect == 1)
        _ = driver.core.restart(at: driver.now)
        #expect(driver.core.stats == PracticeStats())
    }

    @Test func measureNavigation() {
        let long = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 60, beat: 11)])
        let core = TransportCore(song: long, settings: TestSongs.settings())
        #expect(core.previousMeasureStart(from: 2.3) == 2.0)
        #expect(core.previousMeasureStart(from: 2.02) == 0.0)
        #expect(core.previousMeasureStart(from: 0) == 0.0)
        #expect(core.nextMeasureStart(from: 2.3) == 4.0)
        #expect(core.nextMeasureStart(from: 5) == long.duration)
    }

    @Test func speedIsClamped() {
        var settings = PracticeSettings()
        settings.speed = 5
        #expect(settings.speed == 2)
        settings.speed = 0.01
        #expect(settings.speed == 0.1)
        settings.speed = 0.333
        #expect(settings.speed == 0.33)
        settings.transpose = 40
        #expect(settings.transpose == 12)
    }

    @Test func songPedalIsForwarded() {
        let pedal = TestSongs.song([N(pitch: 60, beat: 0, beats: 4)], sustain: [(0, true), (1, false)])
        var driver = CoreDriver(pedal, TestSongs.settings())
        driver.play()
        driver.run(1)
        #expect(driver.log.filter { if case .sustain = $0 { true } else { false } } == [.sustain(isDown: true), .sustain(isDown: false)])
    }
}

@Suite("Judging")
struct JudgingTests {
    /// One right-hand note at 1.0 s.
    let song = TestSongs.song([N(pitch: 60, beat: 2)])

    private func pressing(at seconds: TimeInterval, speed: Double = 1, pitch: UInt8 = 60) -> CoreDriver {
        var driver = CoreDriver(song, TestSongs.settings { $0.speed = speed })
        driver.play()
        driver.run(seconds)
        driver.press(pitch)
        return driver
    }

    @Test func gradesByTimingWindow() {
        #expect(pressing(at: 1.045).judged().map(\.1) == [.perfect])
        #expect(pressing(at: 1.06).judged().map(\.1) == [.good])
        #expect(pressing(at: 1.29).judged().map(\.1) == [.good])
        #expect(pressing(at: 0.97).judged().map(\.1) == [.perfect]) // early
        #expect(pressing(at: 0.75).judged().map(\.1) == [.good])
        let tooEarly = pressing(at: 0.65)
        #expect(tooEarly.judged().isEmpty)
        #expect(tooEarly.core.stats.wrong == 1)
    }

    @Test func missesNotesNotPlayedInTime() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(1.29)
        #expect(driver.core.stats.missed == 0)
        driver.run(0.02)
        #expect(driver.core.stats.missed == 1)
        #expect(driver.core.missedNotes == [0])
        #expect(driver.log.contains(.missed(noteID: 0)))
        driver.press(60)
        #expect(driver.core.stats.wrong == 1) // too late now
    }

    @Test("Windows are in real time whatever the speed")
    func windowsFollowRealTime() {
        // At half speed the note is reached after 2 real seconds.
        #expect(pressing(at: 2.04, speed: 0.5).judged().map(\.1) == [.perfect])
        #expect(pressing(at: 2.08, speed: 0.5).judged().map(\.1) == [.good])
        #expect(pressing(at: 2.62, speed: 0.5).judged().isEmpty)
    }

    @Test func wrongKeysBreakTheStreak() {
        let chords = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 62, beat: 1), N(pitch: 64, beat: 2)])
        var driver = CoreDriver(chords, TestSongs.settings())
        driver.play()
        driver.run(0.01)
        driver.press(60)
        driver.run(0.5)
        driver.press(62)
        #expect(driver.core.stats.streak == 2)
        driver.press(70)
        #expect(driver.core.stats.streak == 0)
        #expect(driver.core.stats.bestStreak == 2)
        #expect(driver.log.contains(.wrongKey(pitch: 70)))
    }

    @Test("Only notes of the practised hands count")
    func otherHandDoesNotCount() {
        let both = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 48, beat: 0, track: 1)])
        var driver = CoreDriver(both, TestSongs.settings { $0.hands = [.right] })
        driver.play()
        driver.run(0.01)
        driver.press(48)
        #expect(driver.core.stats.wrong == 1)
        driver.press(60)
        #expect(driver.core.stats.perfect == 1)
        driver.run(1)
        #expect(driver.core.stats.missed == 0) // the left-hand note is not expected
    }

    @Test("Repeated notes of the same pitch are judged separately")
    func repeatedNotes() {
        let repeated = TestSongs.song([N(pitch: 60, beat: 0, beats: 0.25), N(pitch: 60, beat: 0.5, beats: 0.25)])
        var driver = CoreDriver(repeated, TestSongs.settings())
        driver.play()
        driver.run(0.01)
        driver.press(60)
        driver.release(60)
        driver.run(0.25)
        driver.press(60)
        #expect(driver.judged().map(\.0) == [0, 1])
        driver.run(1)
        #expect(driver.core.stats.missed == 0)
    }

    @Test func transpositionAppliesToSoundAndJudging() {
        var driver = CoreDriver(song, TestSongs.settings { $0.transpose = 2 })
        driver.play()
        driver.run(1.01)
        #expect(driver.log.contains(.noteStarted(id: 0, pitch: 62, velocity: 90)))
        driver.press(60)
        #expect(driver.core.stats.wrong == 1)
        driver.press(62)
        #expect(driver.core.stats.perfect == 1)
    }

    @Test func heldTimeCountsCorrectlyHeldNotes() {
        let long = TestSongs.song([N(pitch: 60, beat: 0, beats: 2)])
        var driver = CoreDriver(long, TestSongs.settings())
        driver.play()
        driver.run(0.001)
        driver.press(60)
        driver.run(0.5)
        #expect(abs(driver.core.stats.heldSeconds - 0.5) < 0.01)
        driver.release(60)
        driver.run(0.3)
        #expect(abs(driver.core.stats.heldSeconds - 0.5) < 0.01)
    }

    @Test func statisticsAndScore() {
        var stats = PracticeStats()
        #expect(stats.accuracyPercent == 100)
        stats.recordHit(.perfect)
        stats.recordHit(.good)
        stats.recordMiss()
        stats.recordWrongKey()
        stats.heldSeconds = 1.25
        #expect(stats.accuracyPercent == 50)
        #expect(stats.score == 100 + 50 - 25 + 12)
        #expect(stats.bestStreak == 2 && stats.streak == 0)
    }
}

@Suite("Practice modes")
struct PracticeModeTests {
    // Right hand: C at 0.5 s, then E+G chord at 1.0 s. Left hand: C3 at 0.5 s.
    let song = TestSongs.song([
        N(pitch: 60, beat: 1), N(pitch: 48, beat: 1, track: 1),
        N(pitch: 64, beat: 2), N(pitch: 67, beat: 2),
    ])

    @Test("Wait mode holds every note of the active hands, chords included")
    func waitMode() {
        var driver = CoreDriver(song, TestSongs.settings { $0.mode = .wait; $0.hands = [.right]; $0.waitTolerance = 0 })
        driver.play()
        driver.run(0.8) // stops at 0.5 s, then the cursor glides back 0.2 s before the note
        #expect(abs(driver.time - 0.3) < 1e-6)
        #expect(abs(driver.core.time(at: driver.now) - 0.5) < 1e-6)
        #expect(driver.core.snapshot(at: driver.now).isWaiting)
        #expect(driver.started().isEmpty)
        driver.press(61)
        #expect(driver.core.stats.wrong == 1)
        driver.press(60)
        #expect(driver.judged().map(\.1) == [.perfect])
        driver.run(0.1) // the cursor moves on from where it is drawn
        #expect(abs(driver.time - 0.4) < 1e-3)
        #expect(driver.started().isEmpty)
        driver.run(0.15) // back at the note: the left hand sounds, my C is not played a second time
        #expect(abs(driver.time - 0.55) < 1e-3)
        #expect(driver.started() == [0])
        driver.run(1) // waits on the chord at 1.0 s and glides back to 0.8 s
        #expect(abs(driver.time - 0.8) < 1e-6)
        driver.press(64)
        driver.run(0.2)
        #expect(abs(driver.time - 0.8) < 1e-6) // G is still missing
        driver.press(67)
        driver.run(0.1)
        #expect(abs(driver.time - 0.9) < 1e-3)
        #expect(driver.core.stats.missed == 0)
    }

    @Test("Wait mode keeps going for a short tolerance before stopping")
    func waitModeTolerance() {
        var driver = CoreDriver(song, TestSongs.settings { $0.mode = .wait; $0.hands = [.right]; $0.waitTolerance = 0.2 })
        driver.play()
        driver.run(0.6) // C is due at 0.5 s: still moving 0.1 s later
        #expect(abs(driver.time - 0.6) < 1e-3)
        #expect(!driver.core.snapshot(at: driver.now).isWaiting)
        #expect(Set(driver.started()) == [0]) // the left hand plays, my C stays silent
        driver.press(60) // within the tolerance: no stop at all
        #expect(driver.judged().map(\.1) == [.perfect])
        driver.run(0.7) // the E+G chord is due at 1.0 s; nothing played: stops at 1.2 s
        #expect(driver.core.snapshot(at: driver.now).isWaiting)
        #expect(driver.time < 1.2 && driver.time > 0.8) // gliding back
        driver.run(2)
        #expect(abs(driver.time - 0.8) < 1e-6)
        driver.press(64)
        driver.press(67) // long after: still accepted, the song was waiting
        #expect(driver.judged().map(\.1) == [.perfect, .perfect, .perfect])
        #expect(driver.core.stats.missed == 0)
        driver.run(0.1)
        #expect(abs(driver.time - 0.9) < 1e-3)
        driver.run(0.5)
        #expect(abs(driver.time - 1.4) < 1e-3)
    }

    @Test("Pausing while the cursor is behind keeps it where it is drawn")
    func pauseAfterRewind() {
        var driver = CoreDriver(song, TestSongs.settings { $0.mode = .wait; $0.hands = [.right]; $0.waitTolerance = 0 })
        driver.play()
        driver.run(0.8)
        driver.press(60)
        driver.run(0.1)
        driver.pause()
        #expect(abs(driver.time - 0.4) < 1e-3)
        driver.play()
        driver.run(0.1)
        #expect(abs(driver.time - 0.5) < 1e-3)
    }

    @Test func waitToleranceIsBounded() {
        var settings = PracticeSettings()
        #expect(settings.waitTolerance == 0.25)
        settings.waitTolerance = 5
        #expect(settings.waitTolerance == 1)
        settings.waitTolerance = -1
        #expect(settings.waitTolerance == 0)
    }

    @Test func listenModeJudgesNothing() {
        var driver = CoreDriver(song, TestSongs.settings { $0.mode = .listen })
        driver.play()
        driver.run(0.5)
        driver.press(60)
        driver.run(2)
        #expect(driver.core.stats == PracticeStats())
        #expect(driver.started().count == 4)
    }

    @Test("Don't play my part: active notes only sound when played")
    func muteMyPart() {
        var driver = CoreDriver(song, TestSongs.settings { $0.muteMyPart = true; $0.hands = [.right] })
        driver.play()
        driver.run(0.45)
        driver.press(60) // early hit: it will sound
        driver.run(0.7)
        let started = Set(driver.started())
        #expect(started.contains(0) && started.contains(1)) // played C and the left hand
        #expect(!started.contains(2) && !started.contains(3)) // E and G were not played
    }

    @Test func mutedTracksAreSilent() {
        var driver = CoreDriver(song, TestSongs.settings { $0.mutedTracks = [1] })
        driver.play()
        driver.run(1.5)
        #expect(!driver.started().contains(0)) // note 0 is the left-hand C3 (sorted first by pitch)
        #expect(driver.started().count == 3)
    }
}

@Suite("Loop, count-in and metronome")
struct TimingFeatureTests {
    /// Three 4/4 measures of 2 s each.
    let song = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 62, beat: 4), N(pitch: 64, beat: 8, beats: 4)])

    @Test func loopsOverTheChosenMeasures() {
        var driver = CoreDriver(song, TestSongs.settings { $0.loop = LoopRange(firstMeasure: 1, lastMeasure: 1) })
        #expect(driver.time == 2.0) // starts at the loop
        driver.play()
        driver.run(2.1)
        #expect(driver.count { $0 == .loopRestarted } == 1)
        #expect(abs(driver.time - 2.1) < 0.002)
        #expect(driver.started().filter { $0 == 1 }.count == 2)
        #expect(!driver.started().contains(2)) // never reaches the third measure
    }

    @Test func loopRestartsWithACountIn() {
        var driver = CoreDriver(song, TestSongs.settings { $0.loop = LoopRange(firstMeasure: 1, lastMeasure: 1); $0.countdownEnabled = true })
        driver.play()
        #expect(driver.core.state == .countingDown)
        driver.run(2.0 + 2.0 + 0.01)
        #expect(driver.count { $0 == .loopRestarted } == 1)
        #expect(driver.core.state == .countingDown)
    }

    @Test func countInFollowsTheMeterAndTempo() {
        let waltz = TestSongs.song([N(pitch: 60, beat: 0)], meter: TimeSignature(3, 4))
        var driver = CoreDriver(waltz, TestSongs.settings { $0.countdownEnabled = true })
        driver.play()
        #expect(driver.log == [.countdownBeat(remaining: 3, total: 3)])
        driver.run(0.49)
        #expect(driver.log.count == 1)
        driver.run(0.02)
        #expect(driver.log.last == .countdownBeat(remaining: 2, total: 3))
        driver.run(1.0)
        #expect(driver.count { if case .countdownBeat = $0 { true } else { false } } == 3)
        #expect(driver.core.state == .playing)
        #expect(abs(driver.time - 0.01) < 0.002)
    }

    @Test func countInUsesTheMeasureAfterAPickup() {
        let ppq = 480
        let tempo = TempoMap(ticksPerQuarter: ppq, bpm: 120)
        let signatures = [TimeSignatureChange(tick: 0, signature: TimeSignature(1, 4)), TimeSignatureChange(tick: 480, signature: TimeSignature(3, 4))]
        let song = Song(
            tracks: [Track(sourceIndex: 0)],
            notes: [Note(id: 0, pitch: 60, velocity: 80, track: 0, startTick: 0, durationTicks: 480, start: 0, duration: 0.5, measureIndex: 0)],
            measures: MeasureBuilder.measures(timeSignatures: signatures, endTick: 1920, tempoMap: tempo),
            tempoMap: tempo, timeSignatures: signatures, keySignatures: []
        )
        var core = TransportCore(song: song, settings: TestSongs.settings { $0.countdownEnabled = true; $0.speed = 0.5 })
        #expect(core.play(at: 0) == [.countdownBeat(remaining: 3, total: 3)])
        #expect(core.advance(to: 0.99).isEmpty) // half speed: beats last 1 s
        #expect(core.advance(to: 1.0) == [.countdownBeat(remaining: 2, total: 3)])
    }

    @Test func metronomeClicksOnBeatsWithAccents() {
        var driver = CoreDriver(song, TestSongs.settings { $0.metronome.isEnabled = true })
        driver.play()
        driver.run(6.5)
        let clicks = driver.log.compactMap { if case let .metronomeClick(accent) = $0 { accent } else { nil } }
        #expect(clicks.count == 12)
        #expect(clicks.filter { $0 }.count == 3)
        #expect(clicks.first == true)
    }

    @Test func metronomeSubdivisionsAndCompoundMeter() {
        var doubled = CoreDriver(song, TestSongs.settings { $0.metronome.isEnabled = true; $0.metronome.clicksPerBeat = 2 })
        doubled.play()
        doubled.run(1.99)
        #expect(doubled.count { if case .metronomeClick = $0 { true } else { false } } == 8)

        let jig = TestSongs.song([N(pitch: 60, beat: 0, beats: 6)], meter: TimeSignature(6, 8))
        var compound = CoreDriver(jig, TestSongs.settings { $0.metronome.isEnabled = true })
        compound.play()
        compound.run(3.5)
        let clicks = compound.log.compactMap { if case let .metronomeClick(accent) = $0 { accent } else { nil } }
        #expect(clicks.count == 12) // eighth-note beats, two measures
        #expect(clicks.filter { $0 }.count == 2)
    }
}

@Suite("Real-time engine")
struct PracticeEngineTests {
    final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval = 50
        var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    final class RecordingOutput: NoteOutput, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var played: [UInt8] = []
        func noteOn(_ pitch: UInt8, velocity: UInt8) { lock.lock(); played.append(pitch); lock.unlock() }
        func noteOff(_ pitch: UInt8) {}
        func setSustain(_ isDown: Bool) {}
        func allNotesOff() {}
    }

    @Test func drivesTheOutputAndAcceptsConcurrentInput() async {
        let clock = FakeClock()
        let output = RecordingOutput()
        let song = TestSongs.song((0..<16).map { N(pitch: 60 + UInt8($0 % 12), beat: Double($0) * 0.5, beats: 0.5) })
        let engine = PracticeEngine(song: song, settings: TestSongs.settings(), clock: { clock.now }, output: output)
        engine.play()
        for _ in 0..<990 {
            clock.advance(0.001)
            engine.tick()
        }
        #expect(output.played.count == 4) // notes at 0, 0.25, 0.5 and 0.75 s
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            if i % 2 == 0 {
                engine.handle(InputEvent(kind: .noteOn(pitch: 100, velocity: 64), time: clock.now))
            } else {
                clock.advance(0.0001)
                engine.tick()
            }
        }
        #expect(engine.snapshot().stats.wrong == 100)
        engine.shutdown()
        #expect(engine.snapshot().state == .paused)
    }

    @Test func sessionSummary() {
        var stats = PracticeStats()
        stats.recordHit(.good)
        let summary = SessionSummary(startedAt: Date(), practiceSeconds: 30, settings: TestSongs.settings(), stats: stats, completion: 1.4)
        #expect(summary.completion == 1)
        #expect(summary.isWorthRecording)
        #expect(!SessionSummary(startedAt: Date(), practiceSeconds: 3, settings: TestSongs.settings(), stats: stats, completion: 0).isWorthRecording)
    }
}

@Suite("Settings changes while playing")
struct LiveSettingsTests {
    let song = TestSongs.song([N(pitch: 60, beat: 0, beats: 4), N(pitch: 48, beat: 0, beats: 4, track: 1), N(pitch: 62, beat: 8)])

    @Test func speedChangeKeepsThePosition() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(1)
        var settings = driver.core.settings
        settings.speed = 2
        driver.log += driver.core.update(settings: settings, at: driver.now)
        #expect(abs(driver.time - 1) < 1e-6)
        driver.run(0.5)
        #expect(abs(driver.time - 2) < 1e-6)
    }

    @Test func transposeOrMuteChangesSilenceSoundingNotes() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(0.1)
        var settings = driver.core.settings
        settings.transpose = 1
        let events = driver.core.update(settings: settings, at: driver.now)
        #expect(Set(events) == [.noteEnded(id: 0, pitch: 48), .noteEnded(id: 1, pitch: 60)])
    }

    @Test func handAssignmentAndHandsCanChange() {
        var driver = CoreDriver(song, TestSongs.settings { $0.hands = [.left] })
        let note = song.notes[1] // C4 on track 0
        #expect(driver.core.hand(of: note) == .right)
        #expect(!driver.core.isActive(note))
        var settings = driver.core.settings
        settings.handAssignment = HandAssignment(leftTracks: [0, 1])
        driver.log += driver.core.update(settings: settings, at: driver.now)
        #expect(driver.core.hand(of: note) == .left)
        #expect(driver.core.isActive(note))
        settings.mode = .listen
        driver.log += driver.core.update(settings: settings, at: driver.now)
        #expect(!driver.core.isActive(note))
    }

    @Test func settingALoopMovesIntoIt() {
        var driver = CoreDriver(song, TestSongs.settings())
        var settings = driver.core.settings
        settings.loop = LoopRange(firstMeasure: 1, lastMeasure: 0) // reversed bounds are reordered
        #expect(settings.loop == LoopRange(firstMeasure: 0, lastMeasure: 1))
        settings.loop = LoopRange(firstMeasure: 1, lastMeasure: 1)
        driver.log += driver.core.update(settings: settings, at: driver.now)
        #expect(driver.time == 2)
        #expect(driver.core.loopTimes?.start == 2 && driver.core.loopTimes?.end == 4)
        _ = driver.core.seek(to: 10, at: driver.now)
        #expect(driver.time == 4)
    }

    @Test func countdownCanBePausedAndSlowedDown() {
        var driver = CoreDriver(song, TestSongs.settings { $0.countdownEnabled = true })
        driver.play()
        #expect(driver.core.snapshot(at: driver.now).countdown?.remaining == 4)
        driver.run(0.6)
        #expect(driver.core.snapshot(at: driver.now).countdown?.remaining == 3)
        var settings = driver.core.settings
        settings.speed = 0.5
        driver.log += driver.core.update(settings: settings, at: driver.now)
        driver.log += driver.core.togglePlayback(at: driver.now)
        #expect(driver.core.state == .paused)
        #expect(driver.core.snapshot(at: driver.now).countdown == nil)
        driver.log += driver.core.togglePlayback(at: driver.now)
        #expect(driver.core.state == .countingDown) // still at the very start
        #expect(driver.core.play(at: driver.now).isEmpty) // already counting in
    }

    @Test func snapshotReportsTheMeasureAndJudgements() {
        var driver = CoreDriver(song, TestSongs.settings())
        driver.play()
        driver.run(2.5)
        let snapshot = driver.core.snapshot(at: driver.now)
        #expect(snapshot.measureIndex == 1)
        #expect(snapshot.state == .playing)
        #expect(snapshot.missedNotes == [0, 1])
        #expect(snapshot == driver.core.snapshot(at: driver.now))
    }
}

@Suite("Real-time engine API")
struct PracticeEngineAPITests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _clicks: [ClickSound] = []
        private var _events: [PracticeEvent] = []
        var clicks: [ClickSound] { lock.lock(); defer { lock.unlock() }; return _clicks }
        var events: [PracticeEvent] { lock.lock(); defer { lock.unlock() }; return _events }
        func click(_ sound: ClickSound) { lock.lock(); _clicks.append(sound); lock.unlock() }
        func record(_ events: [PracticeEvent]) { lock.lock(); _events += events; lock.unlock() }
    }

    @Test func transportCommandsClicksAndEvents() {
        let clock = PracticeEngineTests.FakeClock()
        let recorder = Recorder()
        let song = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 62, beat: 4), N(pitch: 64, beat: 8)])
        let engine = PracticeEngine(
            song: song,
            settings: TestSongs.settings { $0.countdownEnabled = true; $0.wrongNoteSound = true },
            clock: { clock.now }, output: nil,
            clickHandler: { sound, _ in recorder.click(sound) },
            onEvents: { recorder.record($0) }
        )
        #expect(engine.song == song)
        engine.play()
        #expect(recorder.clicks == [.accent]) // first count-in beat
        for _ in 0..<2010 { clock.advance(0.001); engine.tick() }
        #expect(recorder.clicks == [.accent, .beat, .beat, .beat])
        #expect(engine.snapshot().state == .playing)

        engine.handle(InputEvent(kind: .noteOn(pitch: 90, velocity: 50), time: clock.now))
        engine.handle(InputEvent(kind: .noteOff(pitch: 90), time: clock.now))
        engine.handle(InputEvent(kind: .sustain(isDown: true), time: clock.now))
        #expect(recorder.clicks.last == .wrongNote)

        engine.update { $0.metronome.isEnabled = true }
        #expect(engine.settings.metronome.isEnabled)
        engine.seekToNextMeasure()
        #expect(abs(engine.snapshot().time - 2) < 1e-6)
        engine.seekToPreviousMeasure()
        #expect(engine.snapshot().time == 0)
        engine.seek(to: 3)
        engine.pause()
        #expect(engine.snapshot().state == .paused)
        engine.togglePlayback()
        #expect(engine.snapshot().state == .playing)
        engine.restart()
        #expect(engine.snapshot().time == 0 && engine.snapshot().stats == PracticeStats())
        engine.update(settings: TestSongs.settings())
        #expect(recorder.events.contains(.wrongKey(pitch: 90)))
    }

    @Test func timerAdvancesOnItsOwn() async throws {
        let song = TestSongs.song([N(pitch: 60, beat: 0, beats: 8)])
        let engine = PracticeEngine(song: song, settings: TestSongs.settings(), output: nil)
        engine.startTimer()
        engine.startTimer() // idempotent
        engine.play()
        try await Task.sleep(for: .milliseconds(150))
        #expect(engine.snapshot().time > 0.05)
        engine.shutdown()
    }
}

@Suite("Input routing")
struct PracticeInputRouterTests {
    @Test func routesToTheAttachedEngineOnly() {
        let song = TestSongs.song([N(pitch: 60, beat: 0, beats: 8)])
        let first = PracticeEngine(song: song, settings: TestSongs.settings(), output: nil)
        let second = PracticeEngine(song: song, settings: TestSongs.settings(), output: nil)
        first.play()
        second.play()
        let router = PracticeInputRouter()
        router.handle(InputEvent(kind: .noteOn(pitch: 90, velocity: 1), time: HostTime.now)) // nothing attached
        router.attach(first)
        router.handle(InputEvent(kind: .noteOn(pitch: 90, velocity: 1), time: HostTime.now))
        router.detach(second) // not current: ignored
        router.handle(InputEvent(kind: .noteOn(pitch: 90, velocity: 1), time: HostTime.now))
        router.detach(first)
        router.handle(InputEvent(kind: .noteOn(pitch: 90, velocity: 1), time: HostTime.now))
        #expect(first.snapshot().stats.wrong == 2)
        #expect(second.snapshot().stats.wrong == 0)
    }
}
