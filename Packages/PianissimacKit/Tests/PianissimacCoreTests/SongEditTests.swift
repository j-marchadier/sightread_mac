import Foundation
import Testing
@testable import PianissimacCore

@Suite("Score editing")
struct SongEditTests {
    private let song = TestSongs.song([
        TestSongs.N(pitch: 60, beat: 0),
        TestSongs.N(pitch: 64, beat: 1),
        TestSongs.N(pitch: 67, beat: 2, beats: 2),
        TestSongs.N(pitch: 48, beat: 0, beats: 4, track: 1),
    ])

    @Test func unchangedNotesKeepTheSong() throws {
        #expect(song.replacingNotes(song.editedNotes) == song)
        let elise = try MIDISongBuilder.song(from: Fixtures.builtinSong("fur-elise.mid"))
        #expect(elise.replacingNotes(elise.editedNotes.shuffled()) == elise)
    }

    @Test func movedNoteGetsNewTimesAndOrder() {
        var notes = song.editedNotes
        // The E (beat 1) moves to beat 3 and up a tone.
        let index = notes.firstIndex { $0.pitch == 64 }!
        notes[index].startTick = 3 * 480
        notes[index].pitch = 66
        let edited = song.replacingNotes(notes)
        #expect(edited.notes.map(\.id) == Array(edited.notes.indices))
        let moved = edited.notes.first { $0.pitch == 66 }!
        #expect(moved.start == 1.5) // beat 3 at 120 BPM
        #expect(moved.duration == 0.5)
        #expect(edited.notes.map(\.startTick) == edited.notes.map(\.startTick).sorted())
        #expect(edited.measures == song.measures)
    }

    @Test func notesPastTheEndAddMeasures() {
        var notes = song.editedNotes
        notes.append(EditedNote(pitch: 72, track: 0, startTick: 9 * 480, durationTicks: 480))
        let edited = song.replacingNotes(notes)
        #expect(edited.measures.count == 3)
        #expect(edited.measures.last?.number == 3)
        #expect(edited.measures.last?.endTick == 12 * 480)
        #expect(edited.notes.last?.measureIndex == 2)
    }

    @Test func invalidValuesAreClamped() {
        let edited = song.replacingNotes([EditedNote(pitch: 200, track: 0, startTick: -10, durationTicks: 0, finger: 9)])
        #expect(edited.notes.first?.pitch == 127)
        #expect(edited.notes.first?.startTick == 0)
        #expect(edited.notes.first?.durationTicks == 1)
        #expect(edited.notes.first?.finger == nil)
    }

    @Test func editedWrittenNotationIsDropped() throws {
        let score = try MusicXMLImporter.song(from: Fixtures.data("MusicXML/two-staves.musicxml"))
        #expect(score.notation != nil)
        #expect(score.replacingNotes(score.editedNotes).notation != nil)
        var notes = score.editedNotes
        notes[0].pitch += 1
        #expect(score.replacingNotes(notes).notation == nil)
    }

    @Test func editsRoundTripThroughJSON() throws {
        let edit = SongEdit(notes: song.editedNotes, editedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try SongEdit.decode(edit.encoded()) == edit)
    }

    @Test func staffStepsGiveWrittenPitches() {
        // Middle line of the treble staff: B4; top line of the bass staff: A3.
        #expect(StaffGeometry.pitch(atStep: 4, clef: .treble, key: nil) == SpelledPitch(step: .b, alter: 0, octave: 4))
        #expect(StaffGeometry.pitch(atStep: 0, clef: .bass, key: nil) == SpelledPitch(step: .a, alter: 0, octave: 3))
        // First ledger line below the treble staff: middle C.
        #expect(StaffGeometry.pitch(atStep: 10, clef: .treble, key: nil).midiPitch == 60)
        // In G major the F line reads F sharp.
        let g = KeySignature(fifths: 1)
        #expect(StaffGeometry.pitch(atStep: 0, clef: .treble, key: g) == SpelledPitch(step: .f, alter: 1, octave: 5))
        for step in -6...14 {
            let pitch = StaffGeometry.pitch(atStep: step, clef: .bass, key: nil)
            #expect(StaffGeometry.step(of: pitch, clef: .bass) == step)
        }
    }

    @Test func noteValueLengths() {
        #expect(NoteValue.quarter.ticks(ticksPerQuarter: 480) == 480)
        #expect(NoteValue.eighth.ticks(ticksPerQuarter: 480) == 240)
        #expect(NoteValue.half.ticks(ticksPerQuarter: 480, dots: 1) == 1440)
        #expect(NoteValue.quarter.ticks(ticksPerQuarter: 480, dots: 2) == 840)
    }
}
