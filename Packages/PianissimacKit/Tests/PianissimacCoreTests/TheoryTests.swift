import Foundation
import Testing
@testable import PianissimacCore

@Suite("Tempo map")
struct TempoMapTests {
    @Test func defaultsTo120BPM() {
        let map = TempoMap(ticksPerQuarter: 480)
        #expect(map.seconds(atTick: 480) == 0.5)
        #expect(map.tick(atSeconds: 1) == 960)
        #expect(map.bpm(atSeconds: 10) == 120)
    }

    @Test("Converts across tempo changes in both directions")
    func convertsAcrossChanges() {
        // 120 BPM for one bar of 4/4, then 60 BPM.
        let map = TempoMap(ticksPerQuarter: 480, changes: [(0, 500_000), (1920, 1_000_000)])
        #expect(map.seconds(atTick: 1920) == 2)
        #expect(map.seconds(atTick: 2400) == 3)
        #expect(map.tick(atSeconds: 3) == 2400)
        #expect(map.bpm(atTick: 2000) == 60)
        for tick in stride(from: 0, through: 5000, by: 37) {
            #expect(map.tick(atSeconds: map.seconds(atTick: tick)) == tick)
        }
    }

    @Test func lastChangeAtATickWins() {
        let map = TempoMap(ticksPerQuarter: 96, changes: [(0, 500_000), (0, 250_000)])
        #expect(map.bpm(atTick: 0) == 240)
        #expect(map.segments.count == 1)
    }
}

@Suite("Key signatures")
struct KeySignatureTests {
    @Test func namesAllFifteenKeys() {
        #expect(KeySignature.allCases.map(\.name) == ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"])
    }

    @Test func alterationsFollowTheOrderOfSharpsAndFlats() {
        let d = KeySignature(fifths: 2)!
        #expect(d.alteredSteps == [.f, .c])
        #expect(d.alteration(for: .f) == 1 && d.alteration(for: .g) == 0)
        let eFlat = KeySignature(fifths: -3)!
        #expect(eFlat.alteredSteps == [.b, .e, .a])
        #expect(eFlat.alteration(for: .a) == -1)
        #expect(KeySignature(fifths: 8) == nil)
    }

    @Test("Transposition keeps the sharp or flat flavour")
    func transposition() {
        let key = { (fifths: Int) in KeySignature(fifths: fifths)! }
        #expect(key(0).transposed(by: 2).name == "D")
        #expect(key(0).transposed(by: 1).name == "C#")
        #expect(key(-1).transposed(by: 1).name == "Gb") // F → G♭ (flat key stays flat)
        #expect(key(2).transposed(by: 4).name == "F#") // D → F♯
        #expect(key(-2).transposed(by: -12) == key(-2))
        for k in KeySignature.allCases {
            for shift in -12...12 {
                #expect(k.transposed(by: shift).tonicPitchClass == ((k.tonicPitchClass + shift) % 12 + 12) % 12)
            }
        }
    }
}

@Suite("Spelling and note names")
struct SpellingTests {
    private func spell(_ pitch: Int, _ fifths: Int?) -> String {
        Speller.spell(pitch, in: fifths.flatMap { KeySignature(fifths: $0) }).description
    }

    @Test func spellsWithTheKey() {
        #expect(spell(61, 0) == "C♯4")
        #expect(spell(61, -5) == "D♭4")
        #expect(spell(66, 1) == "F♯4")
        #expect(spell(65, 1) == "F4") // chromatic natural in G major
        #expect(spell(70, -1) == "B♭4")
        #expect(spell(65, 6) == "E♯4") // diatonic in F♯ major
        #expect(spell(60, 7) == "B♯3") // octave follows the written letter
        #expect(spell(59, -7) == "C♭4")
        #expect(spell(63, nil) == "D♯4")
    }

    @Test("Every pitch keeps its MIDI value whatever the key")
    func spellingPreservesPitch() {
        for key in KeySignature.allCases {
            for pitch in 21...108 {
                #expect(Speller.spell(pitch, in: key).midiPitch == pitch)
            }
        }
    }

    @Test func accidentalAgainstKeyAndInMeasure() {
        let g = KeySignature(fifths: 1)!
        let fNatural = Speller.spell(65, in: g)
        #expect(Speller.accidentalAgainstKey(fNatural, key: g) == .natural)
        #expect(Speller.accidentalAgainstKey(Speller.spell(66, in: g), key: g) == nil)

        var state = MeasureAccidentalState(key: g)
        #expect(state.accidental(for: fNatural) == .natural)
        #expect(state.accidental(for: fNatural) == nil) // already cancelled in this measure
        #expect(state.accidental(for: Speller.spell(66, in: g)) == .sharp) // back to F♯ needs a sharp
        state.reset()
        #expect(state.accidental(for: Speller.spell(66, in: g)) == nil)
    }

    @Test func namesNotesInSolfegeByDefaultAndInLetters() {
        let fSharp = SpelledPitch(step: .f, alter: 1, octave: 4)
        #expect(NoteNamingStyle.solfege.name(of: fSharp) == "Fa♯")
        #expect(NoteNamingStyle.solfege.name(of: SpelledPitch(step: .d, alter: 0, octave: 5), includeOctave: true) == "Ré5")
        #expect(NoteNamingStyle.letters.name(of: SpelledPitch(step: .b, alter: -1, octave: 3)) == "B♭")
    }

    @Test func pianoKeys() {
        #expect(PianoKeys.isBlack(61) && !PianoKeys.isBlack(60))
        #expect(PianoKeys.octave(of: 60) == 4 && PianoKeys.octave(of: 59) == 3 && PianoKeys.octave(of: 21) == 0)
        #expect(PianoKeys.transpose(120, by: 12) == 127)
        #expect(PianoKeys.transpose(5, by: -12) == 0)
    }
}
