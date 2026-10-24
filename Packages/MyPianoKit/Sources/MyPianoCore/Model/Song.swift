import Foundation

/// A piece of music ready to be practised: notes, measures, tempo and key information.
///
/// Positions are kept both in ticks (exact, used for notation) and in seconds at 100 % speed
/// (used for playback and judging). `Song` is an immutable value type; build one with
/// ``MIDISongBuilder`` or ``MusicXMLImporter``.
public struct Song: Sendable, Equatable {
    public var tracks: [Track]
    /// All notes, sorted by start tick then pitch. `notes[i].id == i`.
    public var notes: [Note]
    public var measures: [Measure]
    public var tempoMap: TempoMap
    public var timeSignatures: [TimeSignatureChange]
    /// Key changes. Empty when the key is unknown.
    public var keySignatures: [KeySignatureChange]
    public var sustainChanges: [SustainChange]
    /// Notation details that only score formats carry (MusicXML). `nil` for MIDI files.
    public var notation: NotationHints?

    public init(
        tracks: [Track],
        notes: [Note],
        measures: [Measure],
        tempoMap: TempoMap,
        timeSignatures: [TimeSignatureChange],
        keySignatures: [KeySignatureChange],
        sustainChanges: [SustainChange] = [],
        notation: NotationHints? = nil
    ) {
        self.tracks = tracks
        self.notes = notes
        self.measures = measures
        self.tempoMap = tempoMap
        self.timeSignatures = timeSignatures.isEmpty ? [TimeSignatureChange(tick: 0, signature: .common)] : timeSignatures
        self.keySignatures = keySignatures
        self.sustainChanges = sustainChanges
        self.notation = notation
    }

    /// A song without notes, e.g. for free play.
    public static let empty = Song(
        tracks: [], notes: [], measures: [], tempoMap: TempoMap(ticksPerQuarter: 480, bpm: 120),
        timeSignatures: [], keySignatures: []
    )

    public var ticksPerQuarter: Int { tempoMap.ticksPerQuarter }

    /// End of the last note, in seconds. Trailing silence is ignored.
    public var duration: TimeInterval {
        notes.reduce(0) { max($0, $1.end) }
    }

    /// End of the last measure, in seconds.
    public var scoreDuration: TimeInterval {
        guard let last = measures.last else { return duration }
        return tempoMap.seconds(atTick: last.endTick)
    }

    /// The signature shown on the score: the first one with more than one beat
    /// (single-beat signatures usually mark a pickup measure), otherwise the first one.
    public var primaryTimeSignature: TimeSignature {
        (timeSignatures.first { $0.signature.numerator > 1 } ?? timeSignatures.first)?.signature ?? .common
    }

    /// Key at the start of the piece, or `nil` when unknown.
    public var primaryKeySignature: KeySignature? { keySignatures.first?.key }

    public func timeSignature(atTick tick: Int) -> TimeSignature {
        (timeSignatures.last { $0.tick <= tick } ?? timeSignatures.first)?.signature ?? .common
    }

    public func keySignature(atTick tick: Int) -> KeySignature? {
        (keySignatures.last { $0.tick <= tick } ?? keySignatures.first)?.key
    }

    /// Index of the measure containing `time` (seconds). Times before the first measure map to the first one.
    public func measureIndex(at time: TimeInterval) -> Int {
        guard !measures.isEmpty else { return 0 }
        let tick = tempoMap.tick(atSeconds: time)
        return measureIndex(atTick: tick)
    }

    public func measureIndex(atTick tick: Int) -> Int {
        guard !measures.isEmpty else { return 0 }
        var low = 0
        var high = measures.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if measures[mid].startTick <= tick { low = mid } else { high = mid - 1 }
        }
        return low
    }

    public func notes(inTrack track: Int) -> [Note] {
        notes.filter { $0.track == track }
    }
}

public struct Note: Sendable, Equatable, Identifiable {
    public let id: Int
    public var pitch: UInt8
    public var velocity: UInt8
    public var track: Int
    public var startTick: Int
    public var durationTicks: Int
    public var start: TimeInterval
    public var duration: TimeInterval
    public var measureIndex: Int
    /// Staff given by the score file (1 = upper). `nil` for MIDI files.
    public var staff: Int?

    public init(
        id: Int, pitch: UInt8, velocity: UInt8, track: Int, startTick: Int, durationTicks: Int,
        start: TimeInterval, duration: TimeInterval, measureIndex: Int, staff: Int? = nil
    ) {
        self.id = id
        self.pitch = pitch
        self.velocity = velocity
        self.track = track
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.start = start
        self.duration = duration
        self.measureIndex = measureIndex
        self.staff = staff
    }

    public var end: TimeInterval { start + duration }
    public var endTick: Int { startTick + durationTicks }
}

public struct Track: Sendable, Equatable {
    public var name: String?
    public var program: UInt8?
    public var channel: UInt8?
    /// Position of the track in the source file (MIDI track, or MusicXML part).
    public var sourceIndex: Int

    public init(name: String? = nil, program: UInt8? = nil, channel: UInt8? = nil, sourceIndex: Int) {
        self.name = name
        self.program = program
        self.channel = channel
        self.sourceIndex = sourceIndex
    }

    /// General MIDI channel 10 carries drums.
    public var isPercussion: Bool { channel == 9 }

    /// Matches the track name or a General MIDI piano program (0–6 counts acoustic and electric pianos and harpsichord).
    public var isPiano: Bool {
        if name?.localizedCaseInsensitiveContains("piano") == true { return true }
        if let program, program <= 6 { return true }
        return false
    }
}

public struct Measure: Sendable, Equatable {
    /// Number printed on the score (repeated measures keep their printed number).
    public var number: Int
    public var startTick: Int
    public var endTick: Int
    public var start: TimeInterval
    public var end: TimeInterval

    public init(number: Int, startTick: Int, endTick: Int, start: TimeInterval, end: TimeInterval) {
        self.number = number
        self.startTick = startTick
        self.endTick = endTick
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
    public var ticks: Int { endTick - startTick }
}

public struct TimeSignature: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public var numerator: Int
    public var denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        self.numerator = max(1, numerator)
        self.denominator = max(1, denominator)
    }

    public static let common = TimeSignature(4, 4)

    public func ticksPerMeasure(ticksPerQuarter: Int) -> Int {
        numerator * ticksPerBeat(ticksPerQuarter: ticksPerQuarter)
    }

    /// Length of the denominator unit (a quarter in 4/4, an eighth in 6/8).
    public func ticksPerBeat(ticksPerQuarter: Int) -> Int {
        ticksPerQuarter * 4 / denominator
    }

    public var description: String { "\(numerator)/\(denominator)" }
}

public struct TimeSignatureChange: Sendable, Equatable {
    public var tick: Int
    public var signature: TimeSignature
    public init(tick: Int, signature: TimeSignature) {
        self.tick = tick
        self.signature = signature
    }
}

public struct KeySignatureChange: Sendable, Equatable {
    public var tick: Int
    public var key: KeySignature
    public init(tick: Int, key: KeySignature) {
        self.tick = tick
        self.key = key
    }
}

public struct SustainChange: Sendable, Equatable {
    public var tick: Int
    public var time: TimeInterval
    public var track: Int
    public var isDown: Bool
    public init(tick: Int, time: TimeInterval, track: Int, isDown: Bool) {
        self.tick = tick
        self.time = time
        self.track = track
        self.isDown = isDown
    }
}
