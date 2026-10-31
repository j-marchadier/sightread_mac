import Foundation

/// A score in conventional rhythmic notation, ready to lay out on the grand staff.
///
/// Built from the written notation of a score file when there is one, otherwise by quantizing
/// the MIDI notes (see ``RhythmicScore/init(song:hands:transpose:forcedKey:)``).
public struct RhythmicScore: Sendable {
    public struct Head: Sendable, Equatable {
        public var pitch: SpelledPitch
        public var step: Int
        /// Accidental to print, if any.
        public var accidental: Accidental?
        /// Tied to the same pitch in the next event of the staff.
        public var tiesToNext: Bool
        /// Playable note this head belongs to.
        public var noteID: Int?
    }

    public struct Event: Sendable, Equatable, Identifiable {
        public var id: Int
        public var clef: Clef
        public var measureIndex: Int
        public var startTick: Int
        public var durationTicks: Int
        public var start: TimeInterval
        public var end: TimeInterval
        public var value: NoteValue
        public var dots: Int
        /// 3 for a triplet, `nil` otherwise.
        public var tuplet: Int?
        /// Note heads from lowest to highest. Empty for a rest.
        public var heads: [Head]
        public var stemUp: Bool
        /// Events sharing a group number are beamed together.
        public var beamGroup: Int?
        /// A rest filling a whole measure (drawn centred, whatever the meter).
        public var isMeasureRest: Bool

        public var isRest: Bool { heads.isEmpty }
    }

    public enum Source: Sendable, Equatable {
        /// Written notation read from the file.
        case written
        /// Rhythms guessed from MIDI timing.
        case quantized
    }

    /// Events of both staves, sorted by start tick.
    public let events: [Event]
    public let source: Source
    /// How closely the notes fit the rhythms shown, from 0 to 1 (1 for written notation).
    /// Below about 0.6 the quantized score is hard to read.
    public let quality: Double

    public init(events: [Event], source: Source, quality: Double) {
        self.events = events.sorted { ($0.startTick, $0.clef == .treble ? 0 : 1) < ($1.startTick, $1.clef == .treble ? 0 : 1) }
        self.source = source
        self.quality = quality
    }

    /// Builds the rhythmic score of a song for the hands given (index = note id).
    public init(song: Song, hands: [Hand?], transpose: Int, forcedKey: KeySignature? = nil) {
        if let notation = song.notation, !notation.events.isEmpty {
            self = WrittenNotationBuilder(song: song, hands: hands, transpose: transpose, forcedKey: forcedKey).build(notation)
        } else {
            self = Quantizer(song: song, hands: hands, transpose: transpose, forcedKey: forcedKey).build()
        }
    }
}

// MARK: - Shared helpers

enum NotationRules {
    /// Representable binary durations, longest first, as (ticks, value, dots).
    static func binaryDurations(ppq: Int) -> [(ticks: Int, value: NoteValue, dots: Int)] {
        var result: [(Int, NoteValue, Int)] = []
        for value in [NoteValue.whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond] {
            let base = Int((Double(ppq) * value.quarters).rounded())
            guard base > 0, Double(ppq) * value.quarters == Double(base) else { continue }
            if base % 2 == 0 { result.append((base + base / 2, value, 1)) }
            result.append((base, value, 0))
        }
        return result.sorted { $0.0 > $1.0 }
    }

    /// Closest value for an arbitrary length (used when a file gives no written value).
    static func nearestValue(ticks: Int, ppq: Int) -> (value: NoteValue, dots: Int) {
        let options = binaryDurations(ppq: ppq)
        let best = options.min { abs($0.ticks - ticks) < abs($1.ticks - ticks) }
        return best.map { ($0.value, $0.dots) } ?? (.quarter, 0)
    }

    /// Beat unit used for beaming: a dotted quarter in compound meters (6/8, 9/8, 12/8), else a quarter.
    static func beamUnit(_ signature: TimeSignature, ppq: Int) -> Int {
        if signature.denominator == 8 && signature.numerator % 3 == 0 && signature.numerator > 3 {
            return ppq * 3 / 2
        }
        return ppq
    }

    /// Stem direction: up when the heads lie on average below the middle line.
    static func stemUp(steps: [Int]) -> Bool {
        guard !steps.isEmpty else { return true }
        let average = Double(steps.reduce(0, +)) / Double(steps.count)
        return average >= Double(StaffGeometry.middleLineStep)
    }

    /// Gives beam groups to runs of beamable notes within a beat unit, then aligns their stems.
    static func assignBeams(_ events: inout [RhythmicScore.Event], song: Song) {
        var nextGroup = 0
        for clef in Clef.allCases {
            let indices = events.indices.filter { events[$0].clef == clef }.sorted { events[$0].startTick < events[$1].startTick }
            var run: [Int] = []
            var runKey: (measure: Int, unit: Int)?

            func flush() {
                if run.count >= 2 {
                    let steps = run.flatMap { events[$0].heads.map(\.step) }
                    let up = stemUp(steps: steps)
                    for index in run {
                        events[index].beamGroup = nextGroup
                        events[index].stemUp = up
                    }
                    nextGroup += 1
                }
                run.removeAll()
                runKey = nil
            }

            for index in indices {
                let event = events[index]
                guard !event.isRest, event.value.beamCount > 0, event.measureIndex < song.measures.count else {
                    flush()
                    continue
                }
                let measure = song.measures[event.measureIndex]
                let unit = event.tuplet != nil ? song.ticksPerQuarter : beamUnit(song.timeSignature(atTick: measure.startTick), ppq: song.ticksPerQuarter)
                let key = (event.measureIndex, (event.startTick - measure.startTick) / max(1, unit))
                if let runKey, runKey != key { flush() }
                runKey = key
                run.append(index)
            }
            flush()
        }
    }

    /// Prints accidentals with measure memory; tied continuations never repeat theirs.
    static func assignAccidentals(_ events: inout [RhythmicScore.Event], key: (Int) -> KeySignature?) {
        for clef in Clef.allCases {
            var measure = -1
            var state = MeasureAccidentalState(key: nil)
            var tiedFromPrevious: Set<Int> = [] // diatonic indices tied into the current event
            for index in events.indices where events[index].clef == clef {
                if events[index].measureIndex != measure {
                    measure = events[index].measureIndex
                    state = MeasureAccidentalState(key: key(events[index].startTick))
                }
                var tiedOut: Set<Int> = []
                for h in events[index].heads.indices {
                    let head = events[index].heads[h]
                    if tiedFromPrevious.contains(head.pitch.diatonicIndex) {
                        events[index].heads[h].accidental = nil
                    } else if events[index].heads[h].accidental == nil {
                        events[index].heads[h].accidental = state.accidental(for: head.pitch)
                    } else {
                        _ = state.accidental(for: head.pitch) // keep the measure memory in step with printed ones
                    }
                    if head.tiesToNext { tiedOut.insert(head.pitch.diatonicIndex) }
                }
                tiedFromPrevious = tiedOut
            }
        }
    }
}

// MARK: - Written notation (MusicXML)

struct WrittenNotationBuilder {
    let song: Song
    let hands: [Hand?]
    let transpose: Int
    let forcedKey: KeySignature?

    func key(atTick tick: Int) -> KeySignature? {
        (forcedKey ?? song.keySignature(atTick: tick))?.transposed(by: transpose)
    }

    func build(_ notation: NotationHints) -> RhythmicScore {
        let anyHand = hands.contains { $0 != nil }
        var trackHands: [Int: Hand] = [:]
        for note in song.notes {
            if let hand = hands.indices.contains(note.id) ? hands[note.id] : nil { trackHands[note.track] = hand }
        }
        var events: [RhythmicScore.Event] = []
        for written in notation.events {
            let hand = trackHands[written.track]
            if anyHand && hand == nil { continue }
            let clef: Clef = hand.map { $0 == .right ? .treble : .bass } ?? (written.staff == 1 ? .treble : .bass)
            let heads: [RhythmicScore.Head] = written.pitches.map { pitch in
                var spelling = pitch.spelling
                var printed = pitch.printedAccidental
                if transpose != 0 {
                    spelling = Speller.spell(spelling.midiPitch + transpose, in: key(atTick: written.startTick))
                    printed = nil
                }
                return RhythmicScore.Head(
                    pitch: spelling, step: StaffGeometry.step(of: spelling, clef: clef),
                    accidental: printed, tiesToNext: pitch.tieStart, noteID: pitch.noteID
                )
            }.sorted { $0.pitch.midiPitch < $1.pitch.midiPitch }
            let fallback = NotationRules.nearestValue(ticks: written.durationTicks, ppq: song.ticksPerQuarter)
            let measureTicks = song.measures.indices.contains(written.measureIndex) ? song.measures[written.measureIndex].ticks : 0
            events.append(RhythmicScore.Event(
                id: events.count, clef: clef, measureIndex: written.measureIndex,
                startTick: written.startTick, durationTicks: written.durationTicks,
                start: song.tempoMap.seconds(atTick: written.startTick),
                end: song.tempoMap.seconds(atTick: written.startTick + written.durationTicks),
                value: written.value ?? fallback.value, dots: written.value == nil ? fallback.dots : written.dots,
                tuplet: written.tuplet?.actual, heads: heads,
                stemUp: written.stemUp ?? NotationRules.stemUp(steps: heads.map(\.step)),
                beamGroup: nil,
                isMeasureRest: written.isRest && written.durationTicks == measureTicks
            ))
        }
        // Beams as written: a group runs from "begin" to "end" on the first beam level.
        var group = 0
        var open: [Clef: Int] = [:]
        for (index, written) in zip(events.indices, notation.events.filter { w in !anyHand || trackHands[w.track] != nil }) {
            guard let first = written.beams.first else { continue }
            let clef = events[index].clef
            switch first {
            case .begin:
                open[clef] = group
                group += 1
                events[index].beamGroup = open[clef]
            case .continue:
                events[index].beamGroup = open[clef]
            case .end:
                events[index].beamGroup = open[clef]
                open[clef] = nil
            default:
                break
            }
        }
        NotationRules.assignAccidentals(&events, key: key(atTick:))
        return RhythmicScore(events: events, source: .written, quality: 1)
    }
}
