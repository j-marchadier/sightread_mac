import Foundation

/// Deterministic random numbers (SplitMix64), so a seed always gives the same exercise.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum ExerciseStaff: String, Sendable, Codable, CaseIterable {
    case treble, bass, grand
}

/// Builds a song from notes written in quarter-note beats.
struct ExerciseSongBuilder {
    struct Item {
        var pitch: Int
        var beat: Double
        var beats: Double
        var hand: Hand
    }

    static let ticksPerQuarter = 480

    static func song(_ items: [Item], meter: TimeSignature, measures: Int, bpm: Double, key: KeySignature) -> Song {
        let ppq = ticksPerQuarter
        let tempo = TempoMap(ticksPerQuarter: ppq, bpm: bpm)
        let signatures = [TimeSignatureChange(tick: 0, signature: meter)]
        let endTick = measures * meter.ticksPerMeasure(ticksPerQuarter: ppq)
        var song = Song(
            tracks: [Track(name: "Main droite", program: 0, channel: 0, sourceIndex: 0), Track(name: "Main gauche", program: 0, channel: 1, sourceIndex: 1)],
            notes: [],
            measures: MeasureBuilder.measures(timeSignatures: signatures, endTick: endTick, tempoMap: tempo),
            tempoMap: tempo,
            timeSignatures: signatures,
            keySignatures: [KeySignatureChange(tick: 0, key: key)]
        )
        let sorted = items.sorted { ($0.beat, $0.pitch) < ($1.beat, $1.pitch) }
        song.notes = sorted.enumerated().map { index, item in
            let start = Int((item.beat * Double(ppq)).rounded())
            let end = Int(((item.beat + item.beats) * Double(ppq)).rounded())
            return Note(
                id: index, pitch: UInt8(clamping: item.pitch), velocity: 80, track: item.hand == .right ? 0 : 1,
                startTick: start, durationTicks: end - start, start: tempo.seconds(atTick: start),
                duration: tempo.seconds(atTick: end) - tempo.seconds(atTick: start),
                measureIndex: song.measureIndex(atTick: start)
            )
        }
        return song
    }

    /// Hands of a generated song: track 0 right, track 1 left.
    static let hands = HandAssignment(leftTracks: [1], rightTracks: [0])

    /// Pitches of the key's major scale between two bounds.
    static func scalePitches(_ key: KeySignature, from lower: Int, to upper: Int) -> [Int] {
        let classes = Set(key.scalePitchClasses)
        return (lower...upper).filter { classes.contains($0 % 12) }
    }
}

/// "Note reading": single notes to name on the keyboard, one per beat, in the chosen key.
public struct NoteReadingExercise: Sendable, Equatable, Codable {
    public var staff: ExerciseStaff = .treble
    public var key: KeySignature = .cMajor
    public var noteCount = 20
    /// Use ledger lines just outside the staff.
    public var widerRange = false

    public init(staff: ExerciseStaff = .treble, key: KeySignature = .cMajor, noteCount: Int = 20, widerRange: Bool = false) {
        self.staff = staff
        self.key = key
        self.noteCount = noteCount
        self.widerRange = widerRange
    }

    public static let trebleRange = 64...77 // E4…F5, the treble staff
    public static let bassRange = 43...57 // G2…A3, the bass staff

    public func makeSong(seed: UInt64) -> Song {
        var random = SeededRandom(seed: seed)
        let margin = widerRange ? 4 : 0
        let treble = ExerciseSongBuilder.scalePitches(key, from: Self.trebleRange.lowerBound - margin, to: Self.trebleRange.upperBound + margin)
        let bass = ExerciseSongBuilder.scalePitches(key, from: Self.bassRange.lowerBound - margin, to: Self.bassRange.upperBound + margin)
        var items: [ExerciseSongBuilder.Item] = []
        var previous: Int?
        for index in 0..<max(1, noteCount) {
            let useTreble = staff == .treble || (staff == .grand && Bool.random(using: &random))
            let pool = (useTreble ? treble : bass).filter { $0 != previous }
            let pitch = pool.randomElement(using: &random) ?? 60
            previous = pitch
            items.append(.init(pitch: pitch, beat: Double(index), beats: 1, hand: useTreble ? .right : .left))
        }
        let measures = (max(1, noteCount) + 3) / 4
        return ExerciseSongBuilder.song(items, meter: .common, measures: measures, bpm: 60, key: key)
    }
}

/// "Phrases": short pieces on a chord progression, with rhythms that grow harder with the level.
public struct PhraseExercise: Sendable, Equatable, Codable {
    public var staff: ExerciseStaff = .grand
    /// 0 (long notes) to 3 (eighths, dotted rhythms and broken chords).
    public var level = 0
    public var key: KeySignature = .cMajor
    public var measures = 8

    public init(staff: ExerciseStaff = .grand, level: Int = 0, key: KeySignature = .cMajor, measures: Int = 8) {
        self.staff = staff
        self.level = min(3, max(0, level))
        self.key = key
        self.measures = max(2, measures)
    }

    static let progressions: [[Int]] = [[1, 4, 5, 1], [1, 6, 4, 5], [1, 5, 6, 4], [1, 4, 1, 5], [6, 4, 1, 5]]

    /// Right-hand rhythms per level, as beat lengths filling a 4/4 measure.
    static let rhythms: [[[Double]]] = [
        [[4], [2, 2]],
        [[1, 1, 1, 1], [2, 1, 1], [1, 1, 2]],
        [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 0.5, 0.5, 1], [1, 1, 0.5, 0.5, 1]],
        [[1.5, 0.5, 1, 1], [0.5, 0.5, 0.5, 0.5, 1, 1], [1, 0.75, 0.25, 1, 0.5, 0.5], [0.5, 1, 0.5, 2]],
    ]

    public func makeSong(seed: UInt64) -> Song {
        var random = SeededRandom(seed: seed)
        let progression = Self.progressions.randomElement(using: &random)!
        let tonic = 60 + key.tonicPitchClass - (key.tonicPitchClass > 6 ? 12 : 0)
        let scale = ExerciseSongBuilder.scalePitches(key, from: 55, to: 84)
        let rightRange = 60...79
        var items: [ExerciseSongBuilder.Item] = []
        var melody = scale.filter { rightRange.contains($0) }.min { abs($0 - (tonic + 4)) < abs($1 - (tonic + 4)) } ?? 64

        for measure in 0..<measures {
            let degree = measure == measures - 1 ? 1 : progression[measure % progression.count]
            // Semitones from the tonic to each scale degree.
            let interval = { (index: Int) in (key.scalePitchClasses[index % 7] - key.tonicPitchClass + 12) % 12 }
            let root = tonic + interval(degree - 1)
            let chordTones = [0, 2, 4].map { interval(degree - 1 + $0) }
            let start = Double(measure * 4)

            if staff != .bass {
                let rhythm = measure == measures - 1 ? [4.0] : (Self.rhythms[level].randomElement(using: &random) ?? [4])
                var beat = 0.0
                for (i, length) in rhythm.enumerated() {
                    let strong = beat.truncatingRemainder(dividingBy: 2) == 0
                    let candidates = scale.filter { rightRange.contains($0) && abs($0 - melody) <= (strong ? 5 : 2) && $0 != melody }
                    let chordCandidates = candidates.filter { chordTones.contains(($0 - tonic + 120) % 12) }
                    let pool = (strong || i == rhythm.count - 1) && !chordCandidates.isEmpty ? chordCandidates : candidates
                    if measure == measures - 1 {
                        melody = scale.filter { rightRange.contains($0) && ($0 - tonic + 120) % 12 == 0 }.min { abs($0 - melody) < abs($1 - melody) } ?? tonic
                    } else {
                        melody = pool.randomElement(using: &random) ?? melody
                    }
                    items.append(.init(pitch: melody, beat: start + beat, beats: length, hand: .right))
                    beat += length
                }
            }
            if staff != .treble {
                let bassRoot = root - 24 + (root - 24 < 41 ? 12 : 0)
                let fifth = bassRoot + 7
                let third = bassRoot + (chordTones[1] - chordTones[0] + 12) % 12
                let pattern: [(pitch: Int, beat: Double, beats: Double)]
                switch measure == measures - 1 ? 0 : level {
                case 0: pattern = [(bassRoot, 0, 4)]
                case 1: pattern = [(bassRoot, 0, 2), (fifth, 2, 2)]
                case 2: pattern = [(bassRoot, 0, 1), (fifth, 1, 1), (bassRoot + 12, 2, 1), (fifth, 3, 1)]
                default: pattern = (0..<8).map { i in ([bassRoot, fifth, third + 12, fifth][i % 4], Double(i) * 0.5, 0.5) }
                }
                for note in pattern {
                    items.append(.init(pitch: note.pitch, beat: start + note.beat, beats: note.beats, hand: .left))
                }
            }
        }
        let bpm = [60.0, 72, 80, 88][level]
        return ExerciseSongBuilder.song(items, meter: .common, measures: measures, bpm: bpm, key: key)
    }
}
