#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Testing
@testable import PianissimacCore

@Suite("Fingering")
struct FingeringTests {
    /// Fingers suggested for a melody played by one hand.
    private func fingers(_ pitches: [UInt8], hand: Hand = .right, written: [Int: UInt8] = [:]) -> [UInt8] {
        var song = TestSongs.song(pitches.enumerated().map { TestSongs.N(pitch: $0.element, beat: Double($0.offset)) })
        for (index, finger) in written { song.notes[index].finger = finger }
        let result = FingeringSuggester.fingers(for: song, hands: song.notes.map { _ in hand })
        return result.map { $0?.number ?? 0 }
    }

    @Test func rightHandScales() {
        #expect(fingers([60, 62, 64, 65, 67, 69, 71, 72]) == [1, 2, 3, 1, 2, 3, 4, 5]) // C major
        #expect(fingers([67, 69, 71, 72, 74, 76, 78, 79]) == [1, 2, 3, 1, 2, 3, 4, 5]) // G major
        #expect(fingers([72, 71, 69, 67, 65, 64, 62, 60]) == [5, 4, 3, 2, 1, 3, 2, 1]) // C major down
    }

    @Test func leftHandScales() {
        #expect(fingers([48, 50, 52, 53, 55, 57, 59, 60], hand: .left) == [5, 4, 3, 2, 1, 3, 2, 1])
        #expect(fingers([60, 59, 57, 55, 53, 52, 50, 48], hand: .left) == [1, 2, 3, 1, 2, 3, 4, 5])
    }

    @Test func fivePositionAndArpeggio() {
        #expect(fingers([60, 62, 64, 65, 67, 65, 64, 62, 60]) == [1, 2, 3, 4, 5, 4, 3, 2, 1])
        #expect(fingers([60, 64, 67, 72]) == [1, 2, 3, 5])
    }

    @Test func chords() {
        let song = TestSongs.song([
            .init(pitch: 60, beat: 0), .init(pitch: 64, beat: 0), .init(pitch: 67, beat: 0),
            .init(pitch: 48, beat: 0, track: 1), .init(pitch: 52, beat: 0, track: 1), .init(pitch: 55, beat: 0, track: 1),
        ])
        let hands = song.notes.map { $0.track == 0 ? Hand.right : Hand.left }
        let result = FingeringSuggester.fingers(for: song, hands: hands)
        let byPitch = Dictionary(uniqueKeysWithValues: song.notes.map { ($0.pitch, result[$0.id]!.number) })
        #expect([byPitch[60], byPitch[64], byPitch[67]] == [1, 3, 5])
        #expect([byPitch[48], byPitch[52], byPitch[55]] == [5, 3, 1])
    }

    @Test func writtenFingersAreKept() {
        let result = fingers([60, 62, 64, 65, 67], written: [2: 2])
        #expect(result[2] == 2)
        #expect(result == [1, 1, 2, 3, 4] || result[1] != 2) // never the same finger on two keys in a row
        var song = TestSongs.song([.init(pitch: 60, beat: 0)])
        song.notes[0].finger = 3
        #expect(FingeringSuggester.fingers(for: song, hands: [.right])[0] == Finger(3, isWritten: true))
    }

    @Test func accompanimentHasNoFingers() {
        let song = TestSongs.song([.init(pitch: 60, beat: 0)])
        #expect(FingeringSuggester.fingers(for: song, hands: [nil]) == [nil])
    }
}

@Suite("Fingering of the built-in library")
struct BuiltinFingeringTests {
    @Test("Every practised note gets a finger, quickly", arguments: BuiltinSongExpectation.all.map(\.file))
    func fingersEverySong(_ file: String) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(file))
        let assignment = HandAssigner.assign(song)
        let hands = song.notes.map { assignment.hand(for: $0) }
        // Best of three, in CPU time: parallel tests and builds competing for the cores must not fail
        // the budget, while a slower algorithm still does (about 170 ms in Debug for the slowest song).
        var fingers: [Finger?] = []
        var best = Duration.seconds(60)
        for _ in 0..<3 {
            let start = threadCPUTime()
            fingers = FingeringSuggester.fingers(for: song, hands: hands)
            best = min(best, threadCPUTime() - start)
        }
        #expect(best < .milliseconds(500), "\(file): \(best)")
        // Chords of more than five notes in one hand leave the extra notes without a finger.
        let missing = song.notes.indices.filter { hands[$0] != nil && fingers[$0] == nil }.count
        #expect(Double(missing) <= Double(song.notes.count) * 0.02)
    }
}

/// CPU time used by the calling thread so far; unlike the wall clock, it does not count time spent waiting for a core.
private func threadCPUTime() -> Duration {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
}
