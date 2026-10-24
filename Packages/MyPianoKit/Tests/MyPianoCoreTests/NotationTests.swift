import Foundation
import Testing
@testable import MyPianoCore

private typealias N = TestSongs.N

@Suite("Staff geometry")
struct StaffGeometryTests {
    private func pitch(_ step: Step, _ octave: Int, _ alter: Int = 0) -> SpelledPitch {
        SpelledPitch(step: step, alter: alter, octave: octave)
    }

    @Test func positionsOnBothStaves() {
        #expect(StaffGeometry.step(of: pitch(.f, 5), clef: .treble) == 0)
        #expect(StaffGeometry.step(of: pitch(.e, 4), clef: .treble) == 8)
        #expect(StaffGeometry.step(of: pitch(.c, 4), clef: .treble) == 10)
        #expect(StaffGeometry.step(of: pitch(.a, 3), clef: .bass) == 0)
        #expect(StaffGeometry.step(of: pitch(.g, 2), clef: .bass) == 8)
        #expect(StaffGeometry.step(of: pitch(.c, 4), clef: .bass) == -2)
        #expect(StaffGeometry.step(of: pitch(.b, 3, 1), clef: .treble) == StaffGeometry.step(of: pitch(.b, 3), clef: .treble))
        #expect(Clef.treble.symbolStep == 6 && Clef.bass.symbolStep == 2)
    }

    @Test func ledgerLines() {
        #expect(StaffGeometry.ledgerLineSteps(for: 10) == [10]) // middle C below the treble staff
        #expect(StaffGeometry.ledgerLineSteps(for: 13) == [10, 12])
        #expect(StaffGeometry.ledgerLineSteps(for: -1).isEmpty)
        #expect(StaffGeometry.ledgerLineSteps(for: -3) == [-2])
        #expect(StaffGeometry.ledgerLineSteps(for: -4) == [-2, -4])
        #expect(StaffGeometry.ledgerLineSteps(for: 9).isEmpty)
    }

    @Test func keySignaturePositions() {
        let g = KeySignature(fifths: 1)!
        #expect(StaffGeometry.keySignatureSteps(g, clef: .treble) == [0])
        #expect(StaffGeometry.keySignatureSteps(g, clef: .bass) == [2])
        let eFlat = KeySignature(fifths: -3)!
        #expect(StaffGeometry.keySignatureSteps(eFlat, clef: .treble) == [4, 1, 5])
        #expect(StaffGeometry.keySignatureSteps(.cMajor, clef: .treble).isEmpty)
        #expect(StaffGeometry.keySignatureSteps(KeySignature(fifths: 7)!, clef: .treble).count == 7)
    }

    @Test func clefForNotes() {
        #expect(Clef.forNote(hand: .left, pitch: 80) == .bass)
        #expect(Clef.forNote(hand: nil, pitch: 60) == .treble)
        #expect(Clef.forNote(hand: nil, pitch: 59) == .bass)
    }
}

@Suite("Simplified score")
struct SimplifiedScoreTests {
    @Test func accidentalsFollowKeyAndMeasure() {
        var song = TestSongs.song([N(pitch: 65, beat: 0), N(pitch: 65, beat: 1), N(pitch: 66, beat: 2), N(pitch: 65, beat: 4), N(pitch: 48, beat: 4, track: 1)])
        song.keySignatures = [KeySignatureChange(tick: 0, key: KeySignature(fifths: 1)!)] // G major
        let hands = song.notes.map { TestSongs.hands.hand(for: $0) }
        let score = SimplifiedScore(song: song, hands: hands, transpose: 0)
        let treble = score.heads.filter { $0.clef == .treble }
        #expect(treble.map(\.accidental) == [.natural, nil, .sharp, .natural])
        #expect(score.heads.filter { $0.clef == .bass }.map(\.pitch.description) == ["C3"])
        #expect(treble[0].step == 7)
    }

    @Test func accompanimentIsLeftOutWhenHandsAreKnown() {
        let song = TestSongs.song([N(pitch: 60, beat: 0), N(pitch: 72, beat: 0, track: 2)], tracks: 3)
        let hands = song.notes.map { TestSongs.hands.hand(for: $0) }
        #expect(SimplifiedScore(song: song, hands: hands, transpose: 0).heads.map(\.noteID) == [0])
        let all = SimplifiedScore(song: song, hands: [nil, nil], transpose: 0)
        #expect(all.heads.count == 2)
    }

    @Test func transpositionAndForcedKey() {
        let song = TestSongs.song([N(pitch: 61, beat: 0)])
        let flat = SimplifiedScore(song: song, hands: [.right], transpose: 0, forcedKey: KeySignature(fifths: -2))
        #expect(flat.heads[0].pitch.description == "D♭4")
        let up = SimplifiedScore(song: song, hands: [.right], transpose: 1)
        #expect(up.heads[0].pitch.description == "D4" && up.heads[0].accidental == nil)
    }
}

@Suite("Rhythmic notation")
struct RhythmicNotationTests {
    private func score(_ notes: [N], meter: TimeSignature = .common, measures: Int? = nil, jitter: [Int] = []) -> RhythmicScore {
        var song = TestSongs.song(notes, meter: meter, measures: measures)
        for (i, offset) in jitter.enumerated() where i < song.notes.count {
            song.notes[i].startTick += offset
        }
        let hands = song.notes.map { TestSongs.hands.hand(for: $0) }
        return RhythmicScore(song: song, hands: hands, transpose: 0)
    }

    private func treble(_ score: RhythmicScore) -> [RhythmicScore.Event] { score.events.filter { $0.clef == .treble } }

    private func signature(_ event: RhythmicScore.Event) -> String {
        "\(event.isRest ? "r" : "n")\(event.value)\(String(repeating: ".", count: event.dots))\(event.tuplet.map { "/\($0)" } ?? "")"
    }

    @Test func quartersEighthsAndHalves() {
        let result = score([N(pitch: 60, beat: 0), N(pitch: 62, beat: 1, beats: 0.5), N(pitch: 64, beat: 1.5, beats: 0.5), N(pitch: 65, beat: 2, beats: 2)])
        let events = treble(result)
        #expect(events.map(signature) == ["nquarter", "neighth", "neighth", "nhalf"])
        #expect(events[1].beamGroup != nil && events[1].beamGroup == events[2].beamGroup)
        #expect(events[0].beamGroup == nil)
        #expect(result.events.filter { $0.clef == .bass }.allSatisfy { $0.isMeasureRest })
        #expect(result.quality == 1 && result.source == .quantized)
    }

    @Test func humanTimingIsStraightened() {
        let notes = [N(pitch: 60, beat: 0), N(pitch: 62, beat: 1, beats: 0.5), N(pitch: 64, beat: 1.5, beats: 0.5), N(pitch: 65, beat: 2, beats: 2)]
        let result = score(notes, jitter: [12, -25, 18, -9])
        #expect(treble(result).map(signature) == ["nquarter", "neighth", "neighth", "nhalf"])
        #expect(result.quality > 0.5 && result.quality < 1)
    }

    @Test func tripletsAreDetected() {
        let third = 1.0 / 3.0
        let result = score([N(pitch: 60, beat: 0, beats: third), N(pitch: 62, beat: third, beats: third), N(pitch: 64, beat: 2 * third, beats: third), N(pitch: 65, beat: 1, beats: 3)])
        let events = treble(result)
        #expect(events.prefix(3).allSatisfy { $0.tuplet == 3 && $0.value == .eighth })
        #expect(Set(events.prefix(3).map(\.beamGroup)).count == 1 && events[0].beamGroup != nil)
        #expect(events[3].tuplet == nil)
    }

    @Test func notesCrossingBarLinesAreTied() {
        let result = score([N(pitch: 67, beat: 3, beats: 2)], measures: 2)
        let notes = treble(result).filter { !$0.isRest }
        #expect(notes.map(signature) == ["nquarter", "nquarter"])
        #expect(notes.map(\.measureIndex) == [0, 1])
        #expect(notes[0].heads[0].tiesToNext && !notes[1].heads[0].tiesToNext)
        #expect(notes.allSatisfy { $0.heads[0].noteID == 0 })
    }

    @Test func restsFillMeasures() {
        let events = treble(score([N(pitch: 60, beat: 1)], measures: 1))
        #expect(events.map(signature) == ["rquarter", "nquarter", "rhalf"])
        let total = events.reduce(0) { $0 + $1.durationTicks }
        #expect(total == 1920)
    }

    @Test func dottedValues() {
        let events = treble(score([N(pitch: 60, beat: 0, beats: 1.5), N(pitch: 62, beat: 1.5, beats: 0.5), N(pitch: 64, beat: 2, beats: 2)]))
        #expect(events.map(signature) == ["nquarter.", "neighth", "nhalf"])
    }

    @Test func compoundMeterBeamsByThreeEighths() {
        let notes = (0..<6).map { N(pitch: UInt8(60 + $0), beat: Double($0) * 0.5, beats: 0.5) }
        let events = treble(score(notes, meter: TimeSignature(6, 8)))
        #expect(events.count == 6)
        let groups = events.map(\.beamGroup)
        #expect(groups[0] == groups[1] && groups[1] == groups[2])
        #expect(groups[3] == groups[4] && groups[4] == groups[5])
        #expect(groups[0] != groups[3])
    }

    @Test func accidentalsAndTies() {
        let result = score([N(pitch: 66, beat: 0), N(pitch: 66, beat: 1), N(pitch: 66, beat: 3, beats: 2), N(pitch: 66, beat: 6)], measures: 2)
        let notes = treble(result).filter { !$0.isRest }
        #expect(notes.map { $0.heads[0].accidental } == [.sharp, nil, nil, nil, .sharp])
    }

    @Test func stemsPointAwayFromTheMiddle() {
        #expect(NotationRules.stemUp(steps: [8]))
        #expect(!NotationRules.stemUp(steps: [0]))
        #expect(NotationRules.stemUp(steps: [4]))
        #expect(NotationRules.stemUp(steps: []))
        let high = treble(score([N(pitch: 79, beat: 0, beats: 4)]))
        #expect(high[0].stemUp == false && high[0].value == .whole)
    }

    @Test("Built-in songs quantize cleanly and every measure is filled", arguments: BuiltinSongExpectation.all)
    func builtinSongs(_ expected: BuiltinSongExpectation) throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong(expected.file))
        let assignment = HandAssigner.assign(song)
        let hands = song.notes.map { assignment.hand(for: $0) }
        let result = RhythmicScore(song: song, hands: hands, transpose: 0)
        #expect(result.quality > 0.9, "quality \(result.quality)")
        for clef in Clef.allCases {
            let events = result.events.filter { $0.clef == clef }
            guard !events.isEmpty else { continue }
            let perMeasure = Dictionary(grouping: events, by: \.measureIndex).mapValues { $0.reduce(0) { $0 + $1.durationTicks } }
            for (index, ticks) in perMeasure {
                #expect(ticks == song.measures[index].ticks, "measure \(index + 1) of \(clef)")
            }
            #expect(perMeasure.count == song.measures.count)
        }
        let shown = Set(result.events.flatMap { $0.heads.compactMap(\.noteID) })
        let practised = Set(song.notes.filter { hands[$0.id] != nil }.map(\.id))
        #expect(practised.subtracting(shown).count <= practised.count / 20, "most notes appear on the score")
    }

    @Test func writtenNotationFromMusicXML() throws {
        let song = try MusicXMLImporter.song(from: Fixtures.data("MusicXML/two-staves.musicxml"))
        let assignment = HandAssigner.assign(song)
        let result = RhythmicScore(song: song, hands: song.notes.map { assignment.hand(for: $0) }, transpose: 0)
        #expect(result.source == .written && result.quality == 1)
        let treble = treble(result)
        #expect(treble.map(signature) == ["nquarter", "nquarter", "neighth", "neighth", "nquarter", "nhalf", "rhalf"])
        #expect(treble[2].beamGroup != nil && treble[2].beamGroup == treble[3].beamGroup)
        #expect(treble[5].heads.count == 3)
        #expect(treble[4].heads[0].accidental == nil) // F♯ belongs to G major
        let bass = result.events.filter { $0.clef == .bass }
        #expect(bass.map(signature) == ["nwhole", "nhalf", "nhalf"])
        #expect(bass[1].heads[0].accidental == .natural)

        let tied = try MusicXMLImporter.song(from: Fixtures.data("MusicXML/ties-and-tuplets.musicxml"))
        let melody = RhythmicScore(song: tied, hands: tied.notes.map { _ in .right }, transpose: 0)
        let heads = melody.events.filter { !$0.isRest && $0.heads[0].pitch.step == .f }
        #expect(heads.map { $0.heads[0].tiesToNext } == [true, true, false])
        #expect(melody.events.prefix(3).allSatisfy { $0.tuplet == 3 })
        let transposed = RhythmicScore(song: tied, hands: tied.notes.map { _ in .right }, transpose: 2)
        #expect(transposed.events.first?.heads.first?.pitch.description == "C5") // B♭4 + 2
    }
}
