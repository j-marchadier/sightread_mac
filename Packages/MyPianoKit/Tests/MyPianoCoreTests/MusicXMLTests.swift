import Foundation
import Testing
@testable import MyPianoCore

@Suite("MusicXML import")
struct MusicXMLTests {
    private func load(_ name: String) throws -> Song {
        try MusicXMLImporter.song(from: Fixtures.data("MusicXML/\(name)"))
    }

    @Test("Two staves: tracks per staff, chords, backup, key, meter and tempo")
    func twoStaves() throws {
        let song = try load("two-staves.musicxml")
        #expect(song.tracks.map(\.name) == ["Piano (1)", "Piano (2)"])
        #expect(song.ticksPerQuarter == 480)
        #expect(song.primaryKeySignature?.name == "G")
        #expect(song.primaryTimeSignature == TimeSignature(4, 4))
        #expect(abs(song.tempoMap.bpm(atTick: 0) - 100) < 0.01)
        #expect(song.measures.map(\.startTick) == [0, 1920])
        #expect(song.measures.map(\.number) == [1, 2])

        let right = song.notes(inTrack: 0)
        #expect(right.map(\.pitch) == [67, 69, 71, 72, 66, 67, 71, 74])
        #expect(right.map(\.startTick) == [0, 480, 960, 1200, 1440, 1920, 1920, 1920])
        #expect(right.allSatisfy { $0.staff == 1 })
        let left = song.notes(inTrack: 1)
        #expect(left.map(\.pitch) == [43, 53, 50])
        #expect(left.map(\.durationTicks) == [1920, 960, 960])
        #expect(abs(song.notes[1].start - 0) < 1e-9)
        #expect(abs(song.tempoMap.seconds(atTick: 480) - 0.6) < 1e-9)
    }

    @Test("Notation hints keep written values, beams, chords, rests and accidentals")
    func notationHints() throws {
        let song = try load("two-staves.musicxml")
        let events = try #require(song.notation?.events)
        #expect(events.count == 10)
        let upper = events.filter { $0.staff == 1 }
        #expect(upper.map(\.value) == [.quarter, .quarter, .eighth, .eighth, .quarter, .half, .half])
        #expect(upper[2].beams == [.begin] && upper[3].beams == [.end])
        #expect(upper[5].pitches.count == 3)
        #expect(upper[6].isRest)
        #expect(upper[0].stemUp == true)
        let fNatural = try #require(events.first { $0.pitches.first?.spelling == SpelledPitch(step: .f, alter: 0, octave: 3) })
        #expect(fNatural.pitches[0].printedAccidental == .natural)
        // Every written head points at its playable note.
        for event in events where !event.isRest {
            for pitch in event.pitches {
                let id = try #require(pitch.noteID)
                #expect(Int(song.notes[id].pitch) == pitch.spelling.midiPitch)
            }
        }
    }

    @Test("Title, composer and written fingers")
    func fingering() throws {
        let song = try load("fingering.musicxml")
        #expect(song.title == "Petite étude")
        #expect(song.composer == "J. Exemple")
        #expect(song.notes.map(\.pitch) == [60, 62, 64])
        #expect(song.notes.map(\.finger) == [1, nil, 3]) // the tied E keeps its first finger
    }

    @Test("Repeats and voltas are unrolled")
    func repeats() throws {
        let song = try load("repeats.musicxml")
        #expect(song.measures.map(\.number) == [1, 2, 1, 3, 4, 4, 4, 5])
        #expect(song.notes.map(\.pitch) == [60, 62, 60, 64, 65, 67, 65, 67, 65, 67, 72])
        #expect(song.measures.last?.endTick == 8 * 960)
        #expect(song.notes.last?.startTick == 7 * 960)
        #expect(song.primaryKeySignature == .cMajor) // an explicit C major is trusted in scores
    }

    @Test("Ties, triplets, grace notes, divisions and meter changes")
    func tiesAndTuplets() throws {
        let song = try load("ties-and-tuplets.musicxml")
        #expect(song.notes.map(\.pitch) == [70, 72, 74, 75, 77, 79])
        #expect(song.notes.map(\.startTick) == [0, 160, 320, 480, 960, 2880])
        #expect(song.notes[4].durationTicks == 1920) // F tied over three written notes
        #expect(song.notes[5].durationTicks == 720) // dotted quarter after <divisions> changed to 2
        #expect(song.primaryKeySignature?.name == "Bb")
        #expect(song.timeSignatures.map(\.signature) == [TimeSignature(3, 4), TimeSignature(6, 8)])
        #expect(song.timeSignatures.map(\.tick) == [0, 2880])

        let events = try #require(song.notation?.events)
        #expect(events.count == 9) // the grace note is not a timed event
        #expect(events[0].tuplet?.actual == 3 && events[0].tuplet?.normal == 2)
        #expect(events.map(\.beams).prefix(3) == [[.begin], [.continue], [.end]])
        let tiedHeads = events.filter { $0.pitches.first?.spelling.step == .f }
        #expect(tiedHeads.count == 3)
        #expect(tiedHeads.allSatisfy { $0.pitches[0].noteID == 4 })
        #expect(tiedHeads[1].pitches[0].tieStart && tiedHeads[1].pitches[0].tieStop)
        #expect(events.last?.isRest == true && events.last?.dots == 1)
    }

    @Test func timewiseScores() throws {
        let song = try load("timewise.musicxml")
        #expect(song.tracks.map(\.name) == ["Right", "Left"])
        #expect(song.notes.map(\.pitch) == [48, 76])
    }

    @Test func compressedScores() throws {
        let compressed = try load("two-staves.mxl")
        let plain = try load("two-staves.musicxml")
        #expect(compressed == plain)
    }

    @Test func errors() throws {
        #expect(throws: MusicXMLError.notMusicXML) { try load("not-a-score.xml") }
        #expect(throws: MusicXMLError.noNotes) { try load("empty-score.musicxml") }
        #expect(throws: MusicXMLError.invalidCompressedArchive) {
            try MusicXMLImporter.song(from: Data([0x50, 0x4B, 0x03, 0x04, 0, 0]))
        }
        #expect(throws: (any Error).self) { try MusicXMLImporter.song(from: Data("<score-partwise><part>".utf8)) }
    }
}

@Suite("Format detection")
struct SongLoaderTests {
    @Test func detectsFormatsFromContent() throws {
        let midi = try Fixtures.builtinSong("ode-to-joy.mid")
        #expect(SongFileFormat.detect(data: midi, fileExtension: "xml") == .midi)
        #expect(SongFileFormat.detect(data: try Fixtures.data("MusicXML/two-staves.mxl"), fileExtension: nil) == .compressedMusicXML)
        #expect(SongFileFormat.detect(data: try Fixtures.data("MusicXML/repeats.musicxml"), fileExtension: nil) == .musicXML)
        #expect(SongFileFormat.detect(data: Data([1, 2, 3]), fileExtension: "MID") == .midi)
        #expect(SongFileFormat.detect(data: Data([1, 2, 3]), fileExtension: "pdf") == nil)
    }

    @Test func loadsEachFormat() throws {
        #expect(try SongLoader.load(data: Fixtures.builtinSong("ode-to-joy.mid")).notes.count == 62)
        #expect(try SongLoader.load(data: Fixtures.data("MusicXML/two-staves.mxl")).notes.count == 11)
        #expect(throws: SongLoadingError.unsupportedFormat) { try SongLoader.load(data: Data("%PDF-1.7".utf8), fileExtension: "pdf") }
        #expect(throws: SongLoadingError.midi(.truncated)) { try SongLoader.load(data: Data(Array("MThd".utf8) + [0, 0, 0, 6, 0])) }
    }
}
