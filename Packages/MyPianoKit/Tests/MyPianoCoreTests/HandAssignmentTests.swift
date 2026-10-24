import Foundation
import Testing
@testable import MyPianoCore

@Suite("Hand assignment")
struct HandAssignmentTests {
    @Test("Two-track built-in songs: upper track to the right hand", arguments: BuiltinSongExpectation.all.filter { $0.notesPerTrack.count == 2 })
    func twoTrackSongs(_ expected: BuiltinSongExpectation) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(expected.file))
        let hands = HandAssigner.assign(song)
        #expect(hands.rightTracks == [0])
        #expect(hands.leftTracks == [1])
        #expect(hands.splitTracks.isEmpty)
    }

    @Test("Single-track melodies go to the right hand, unsplit", arguments: ["la-cucaracha.mid", "ode-to-joy.mid", "twinkle-twinkle-little-star.mid"])
    func singleTrackMelodies(_ file: String) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(file))
        #expect(HandAssigner.assign(song) == HandAssignment(rightTracks: [0]))
    }

    @Test("A single track holding both hands is split at middle C")
    func splitsMergedPianoTrack() throws {
        // Merge both tracks of Für Elise into one.
        var song = try MIDISongBuilder.song(from: Fixtures.builtinSong("fur-elise.mid"))
        song.notes = song.notes.map { var n = $0; n.track = 0; return n }
        song.tracks = [song.tracks[0]]
        let hands = HandAssigner.assign(song)
        #expect(hands.splitTracks == [0: 60])
        let note = song.notes.first { $0.pitch < 60 }!
        #expect(hands.hand(for: note) == .left)
    }

    @Test("Track names win over pitch")
    func namedTracks() {
        let song = Song(
            tracks: [Track(name: "Left Hand", sourceIndex: 0), Track(name: "RH", sourceIndex: 1)],
            notes: [
                Note(id: 0, pitch: 80, velocity: 80, track: 0, startTick: 0, durationTicks: 10, start: 0, duration: 0.1, measureIndex: 0),
                Note(id: 1, pitch: 40, velocity: 80, track: 1, startTick: 0, durationTicks: 10, start: 0, duration: 0.1, measureIndex: 0),
            ],
            measures: [], tempoMap: TempoMap(ticksPerQuarter: 480), timeSignatures: [], keySignatures: []
        )
        #expect(HandAssigner.assign(song) == HandAssignment(leftTracks: [0], rightTracks: [1]))
    }

    @Test("Scores: upper staff is the right hand")
    func staves() throws {
        let song = try MusicXMLImporter.song(from: Fixtures.data("MusicXML/two-staves.musicxml"))
        #expect(HandAssigner.assign(song) == HandAssignment(leftTracks: [1], rightTracks: [0]))
        let parts = try MusicXMLImporter.song(from: Fixtures.data("MusicXML/timewise.musicxml"))
        #expect(HandAssigner.assign(parts) == HandAssignment(leftTracks: [1], rightTracks: [0])) // by name
    }

    @Test func percussionIsNeverAHand() {
        let song = Song(
            tracks: [Track(channel: 9, sourceIndex: 0), Track(program: 0, channel: 0, sourceIndex: 1)],
            notes: [
                Note(id: 0, pitch: 36, velocity: 80, track: 0, startTick: 0, durationTicks: 10, start: 0, duration: 0.1, measureIndex: 0),
                Note(id: 1, pitch: 72, velocity: 80, track: 1, startTick: 0, durationTicks: 10, start: 0, duration: 0.1, measureIndex: 0),
            ],
            measures: [], tempoMap: TempoMap(ticksPerQuarter: 480), timeSignatures: [], keySignatures: []
        )
        #expect(HandAssigner.assign(song) == HandAssignment(rightTracks: [1]))
    }
}
