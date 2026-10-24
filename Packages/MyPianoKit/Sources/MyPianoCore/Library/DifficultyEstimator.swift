import Foundation

/// Rates how hard a song is to play, from 1 to 5, from what its notes demand:
/// notes per second, chords, hand stretch, black keys and how much both hands play at once.
public enum DifficultyEstimator {
    public struct Measures: Sendable, Equatable {
        public var notesPerSecond: Double
        public var averageChordSize: Double
        public var range: Int
        public var blackKeyShare: Double
        public var score: Double
    }

    public static func measure(_ song: Song) -> Measures {
        let notes = song.notes
        guard !notes.isEmpty, song.duration > 0 else {
            return Measures(notesPerSecond: 0, averageChordSize: 0, range: 0, blackKeyShare: 0, score: 0)
        }
        let notesPerSecond = Double(notes.count) / song.duration
        let onsets = Dictionary(grouping: notes, by: \.startTick)
        let averageChordSize = Double(notes.count) / Double(onsets.count)
        let pitches = notes.map { Int($0.pitch) }
        let range = (pitches.max() ?? 0) - (pitches.min() ?? 0)
        let blackKeyShare = Double(notes.filter { PianoKeys.isBlack($0.pitch) }.count) / Double(notes.count)
        let score = notesPerSecond * 0.9
            + (averageChordSize - 1) * 1.6
            + Double(range) / 12 * 0.6
            + blackKeyShare * 2.5
        return Measures(notesPerSecond: notesPerSecond, averageChordSize: averageChordSize, range: range, blackKeyShare: blackKeyShare, score: score)
    }

    public static func rating(for song: Song) -> Int {
        let score = measure(song).score
        switch score {
        case ..<3: return 1
        case ..<5: return 2
        case ..<7.5: return 3
        case ..<10: return 4
        default: return 5
        }
    }
}
