import Foundation
import Testing
@testable import MyPianoCore

/// Facts about the built-in MIDI files. Measures, meter, score length and key come from the
/// scores' published metadata; note counts per track were counted independently from the raw files.
struct BuiltinSongExpectation: Sendable, CustomTestStringConvertible {
    let file: String
    let measures: Int?
    let timeSignature: TimeSignature?
    /// Length up to the end of the last measure, in whole seconds.
    let scoreSeconds: Double?
    /// Expected key when the file declares a non-C key.
    let fifths: Int?
    let notesPerTrack: [Int]

    var testDescription: String { file }

    static let all: [BuiltinSongExpectation] = [
        .init(file: "arabesques.mid", measures: 107, timeSignature: .init(4, 4), scoreSeconds: 215, fifths: 4, notesPerTrack: [748, 707]),
        .init(file: "canon-in-d.mid", measures: 53, timeSignature: .init(4, 4), scoreSeconds: 127, fifths: nil, notesPerTrack: [294, 177]),
        .init(file: "clair-de-lune.mid", measures: 72, timeSignature: .init(9, 8), scoreSeconds: 247, fifths: nil, notesPerTrack: [669, 794]),
        .init(file: "fur-elise.mid", measures: 127, timeSignature: .init(3, 8), scoreSeconds: 148, fifths: nil, notesPerTrack: [635, 412]),
        .init(file: "greensleeves.mid", measures: 49, timeSignature: .init(3, 4), scoreSeconds: 74, fifths: nil, notesPerTrack: [114, 142]),
        .init(file: "gymnopedie-no1.mid", measures: 78, timeSignature: .init(3, 4), scoreSeconds: 185, fifths: 2, notesPerTrack: [279, 176]),
        .init(file: "in-the-hall-of-the-mountain-king.mid", measures: 49, timeSignature: .init(4, 4), scoreSeconds: 98, fifths: nil, notesPerTrack: [335, 290]),
        .init(file: "la-cucaracha.mid", measures: 24, timeSignature: .init(2, 2), scoreSeconds: 48, fifths: 2, notesPerTrack: [99]),
        .init(file: "march-in-d-major.mid", measures: 48, timeSignature: .init(2, 2), scoreSeconds: 73, fifths: nil, notesPerTrack: [254, 184]),
        .init(file: "minuet-in-g-major.mid", measures: 64, timeSignature: .init(3, 4), scoreSeconds: 91, fifths: nil, notesPerTrack: [258, 150]),
        .init(file: "moonlight-sonata.mid", measures: 69, timeSignature: .init(2, 2), scoreSeconds: 294, fifths: 4, notesPerTrack: [924, 245]),
        .init(file: "ode-to-joy.mid", measures: 16, timeSignature: .init(4, 4), scoreSeconds: 32, fifths: 1, notesPerTrack: [62]),
        .init(file: "rondo-alla-turca.mid", measures: 223, timeSignature: .init(2, 4), scoreSeconds: 222, fifths: nil, notesPerTrack: [1484, 1318]),
        .init(file: "sonata-no-11.mid", measures: 36, timeSignature: .init(6, 8), scoreSeconds: 54, fifths: 3, notesPerTrack: [236, 244]),
        .init(file: "the-entertainer.mid", measures: 36, timeSignature: .init(4, 4), scoreSeconds: 72, fifths: nil, notesPerTrack: [180, 169]),
        .init(file: "twinkle-twinkle-little-star.mid", measures: nil, timeSignature: nil, scoreSeconds: nil, fifths: nil, notesPerTrack: [42]),
    ]
}

@Suite("MIDI parsing of the built-in library")
struct MIDIParsingTests {
    @Test("Every built-in file has an expectation")
    func everyFileIsCovered() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Fixtures.builtinSongs.path)
            .filter { $0.hasSuffix(".mid") }
        #expect(Set(files) == Set(BuiltinSongExpectation.all.map(\.file)))
    }

    @Test("Parses notes, measures, meter, length and key", arguments: BuiltinSongExpectation.all)
    func parsesBuiltinSong(_ expected: BuiltinSongExpectation) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(expected.file))

        #expect(song.tracks.map { song.notes(inTrack: song.tracks.firstIndex(of: $0)!).count } == expected.notesPerTrack)
        if let measures = expected.measures {
            #expect(song.measures.count == measures)
        }
        if let signature = expected.timeSignature {
            #expect(song.primaryTimeSignature == signature)
        }
        if let seconds = expected.scoreSeconds {
            #expect(abs(song.scoreDuration - seconds) <= 0.5, "score length \(song.scoreDuration)")
        }
        if let fifths = expected.fifths {
            #expect(song.primaryKeySignature?.fifths == fifths)
        }
        #expect(song.duration > 0)
        #expect(song.duration <= song.scoreDuration + 0.001)
    }

    @Test("Notes are sorted, identified by index and placed in their measure", arguments: BuiltinSongExpectation.all)
    func noteInvariants(_ expected: BuiltinSongExpectation) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(expected.file))
        for (index, note) in song.notes.enumerated() {
            #expect(note.id == index)
            let measure = song.measures[note.measureIndex]
            #expect(measure.startTick <= note.startTick && note.startTick < measure.endTick)
            #expect(abs(note.start - song.tempoMap.seconds(atTick: note.startTick)) < 1e-9)
        }
        #expect(zip(song.notes, song.notes.dropFirst()).allSatisfy { $0.startTick <= $1.startTick })
        #expect(zip(song.measures, song.measures.dropFirst()).allSatisfy { $0.endTick == $1.startTick })
    }

    @Test("Writing then reading keeps notes, measures, meter and key", arguments: BuiltinSongExpectation.all)
    func roundTrip(_ expected: BuiltinSongExpectation) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(expected.file))
        let reread = try MIDISongBuilder.song(from: MIDIFileWriter.data(for: song))

        #expect(reread.notes.count == song.notes.count)
        #expect(reread.measures.count == song.measures.count)
        #expect(reread.primaryTimeSignature == song.primaryTimeSignature)
        #expect(reread.primaryKeySignature == song.primaryKeySignature)
        #expect(abs(reread.duration - song.duration) < 0.001)
        for (a, b) in zip(song.notes, reread.notes) {
            #expect(a.pitch == b.pitch && a.startTick == b.startTick && a.durationTicks == b.durationTicks && a.velocity == b.velocity)
        }
    }
}

@Suite("MIDI file reader")
struct MIDIFileReaderTests {
    @Test func rejectsNonMIDIData() {
        #expect(throws: MIDIFileError.notAMIDIFile) { try MIDIFileReader.read(Data("hello world".utf8)) }
    }

    @Test func rejectsSMPTEDivision() {
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0xE7, 0x28]
        #expect(throws: MIDIFileError.unsupportedTimeDivision) { try MIDIFileReader.read(Data(header)) }
    }

    @Test func rejectsFormat2() {
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 2, 0, 1, 0x01, 0xE0]
        #expect(throws: MIDIFileError.unsupportedFormat(2)) { try MIDIFileReader.read(Data(header)) }
    }

    @Test func rejectsHeaderWithoutTracks() {
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 1, 0x01, 0xE0]
        #expect(throws: MIDIFileError.noTracks) { try MIDIFileReader.read(Data(header)) }
    }

    @Test("Running status, velocity-0 note-offs and a track length past the end of the file")
    func toleratesCommonDefects() throws {
        // Note on C4, then running-status note on with velocity 0 (= note off) 480 ticks later.
        let events: [UInt8] = [0x00, 0x90, 60, 100, 0x83, 0x60, 60, 0]
        let bytes: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
            + Array("MTrk".utf8) + [0, 0, 0x10, 0x00] + events // declared length far too long
        let song = try MIDISongBuilder.song(from: Data(bytes))
        #expect(song.notes.count == 1)
        #expect(song.notes[0].pitch == 60)
        #expect(song.notes[0].durationTicks == 480)
        #expect(abs(song.notes[0].duration - 0.5) < 1e-9) // default 120 BPM
    }

    @Test("Format 0 files are split into one track per channel")
    func splitsFormat0ByChannel() throws {
        let events: [UInt8] = [
            0x00, 0xFF, 0x03, 0x04] + Array("Solo".utf8) + [
            0x00, 0x90, 72, 90, // right hand on channel 0
            0x00, 0x91, 48, 80, // left hand on channel 1
            0x83, 0x60, 0x80, 72, 0,
            0x00, 0x81, 48, 0,
            0x00, 0xFF, 0x2F, 0x00,
        ]
        let bytes: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
            + Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events
        let song = try MIDISongBuilder.song(from: Data(bytes))
        #expect(song.tracks.count == 2)
        #expect(song.tracks.map(\.channel) == [0, 1])
        #expect(song.tracks.allSatisfy { $0.name == "Solo" })
        #expect(song.notes(inTrack: 0).map(\.pitch) == [72])
        #expect(song.notes(inTrack: 1).map(\.pitch) == [48])
    }

    @Test("Sustain pedal events are kept")
    func readsSustainPedal() throws {
        let events: [UInt8] = [
            0x00, 0xB0, 64, 127,
            0x00, 0x90, 60, 100,
            0x83, 0x60, 0x80, 60, 0,
            0x00, 0xB0, 64, 0,
            0x00, 0xFF, 0x2F, 0x00,
        ]
        let bytes: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
            + Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events
        let song = try MIDISongBuilder.song(from: Data(bytes))
        #expect(song.sustainChanges.map(\.isDown) == [true, false])
        #expect(song.sustainChanges.map(\.tick) == [0, 480])
    }
}
