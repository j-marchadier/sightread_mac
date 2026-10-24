import Foundation
@testable import MyPianoCore

/// Builds small songs for engine tests. At the default 120 BPM one beat lasts 0.5 s.
enum TestSongs {
    struct N {
        var pitch: UInt8
        var beat: Double
        var beats: Double = 1
        var track = 0
    }

    static func song(
        _ notes: [N],
        tracks: Int = 2,
        meter: TimeSignature = .common,
        bpm: Double = 120,
        measures: Int? = nil,
        sustain: [(beat: Double, down: Bool)] = []
    ) -> Song {
        let ppq = 480
        let tempo = TempoMap(ticksPerQuarter: ppq, bpm: bpm)
        let quarterTicks = { (beats: Double) in Int((beats * Double(ppq)).rounded()) }
        let signatures = [TimeSignatureChange(tick: 0, signature: meter)]
        let lastEnd = notes.map { quarterTicks($0.beat + $0.beats) }.max() ?? 0
        let measureLength = meter.ticksPerMeasure(ticksPerQuarter: ppq)
        let endTick = measures.map { $0 * measureLength } ?? lastEnd
        var song = Song(
            tracks: (0..<tracks).map { Track(name: "T\($0)", sourceIndex: $0) },
            notes: [],
            measures: MeasureBuilder.measures(timeSignatures: signatures, endTick: endTick, tempoMap: tempo),
            tempoMap: tempo,
            timeSignatures: signatures,
            keySignatures: [],
            sustainChanges: sustain.map {
                let tick = quarterTicks($0.beat)
                return SustainChange(tick: tick, time: tempo.seconds(atTick: tick), track: 0, isDown: $0.down)
            }
        )
        let sorted = notes.sorted { ($0.beat, $0.pitch) < ($1.beat, $1.pitch) }
        song.notes = sorted.enumerated().map { index, n in
            let start = quarterTicks(n.beat)
            let end = quarterTicks(n.beat + n.beats)
            return Note(
                id: index, pitch: n.pitch, velocity: 90, track: n.track, startTick: start, durationTicks: end - start,
                start: tempo.seconds(atTick: start), duration: tempo.seconds(atTick: end) - tempo.seconds(atTick: start),
                measureIndex: song.measureIndex(atTick: start)
            )
        }
        return song
    }

    /// Track 0 = right hand, track 1 = left hand.
    static let hands = HandAssignment(leftTracks: [1], rightTracks: [0])

    static func settings(_ change: (inout PracticeSettings) -> Void = { _ in }) -> PracticeSettings {
        var settings = PracticeSettings(handAssignment: hands)
        settings.countdownEnabled = false
        change(&settings)
        return settings
    }
}

/// Drives a core like the real-time timer would, with a simulated clock.
struct CoreDriver {
    var core: TransportCore
    var now: TimeInterval = 100
    var log: [PracticeEvent] = []

    init(_ song: Song, _ settings: PracticeSettings) {
        core = TransportCore(song: song, settings: settings)
    }

    mutating func play() { log += core.play(at: now) }
    mutating func pause() { log += core.pause(at: now) }

    /// Advances real time in 1 ms steps.
    mutating func run(_ seconds: TimeInterval) {
        let end = now + seconds
        while now < end - 1e-9 {
            now = min(end, now + 0.001)
            log += core.advance(to: now)
        }
    }

    mutating func press(_ pitch: UInt8) {
        log += core.noteOn(pitch, at: now)
    }

    mutating func release(_ pitch: UInt8) {
        core.noteOff(pitch)
    }

    var time: TimeInterval { core.displayTime(at: now) }

    func started() -> [Int] {
        log.compactMap { if case let .noteStarted(id, _, _) = $0 { id } else { nil } }
    }

    func judged() -> [(Int, Grade)] {
        log.compactMap { if case let .judged(id, grade, _) = $0 { (id, grade) } else { nil } }
    }

    func count(_ match: (PracticeEvent) -> Bool) -> Int {
        log.filter(match).count
    }
}
