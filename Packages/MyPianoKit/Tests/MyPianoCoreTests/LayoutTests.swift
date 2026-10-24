import Foundation
import Testing
@testable import MyPianoCore

@Suite("Keyboard and falling-notes layout")
struct LayoutTests {
    @Test func fullKeyboardHas52WhiteKeys() {
        let keyboard = KeyboardLayout(range: 21...108, width: 1040)
        #expect(keyboard.keys.count == 88)
        #expect(keyboard.keys.filter { !$0.isBlack }.count == 52)
        #expect(abs(keyboard.whiteKeyWidth - 20) < 1e-9)
        #expect(keyboard.key(for: 21)?.x == 0)
        #expect(abs((keyboard.key(for: 108)?.maxX ?? 0) - 1040) < 1e-9)
        #expect(keyboard.key(for: 20) == nil)
    }

    @Test func rangesStartAndEndOnWhiteKeys() {
        let keyboard = KeyboardLayout(range: 61...70, width: 700)
        #expect(keyboard.range == 60...71)
    }

    @Test func blackKeysSitBetweenTheirNeighbours() throws {
        let keyboard = KeyboardLayout(range: 60...71, width: 700)
        let c = try #require(keyboard.key(for: 60))
        let cSharp = try #require(keyboard.key(for: 61))
        let d = try #require(keyboard.key(for: 62))
        #expect(cSharp.isBlack && cSharp.width < c.width)
        #expect(cSharp.x > c.x && cSharp.maxX < d.maxX)
        #expect(cSharp.midX < d.x) // shifted left, as on a real piano
        let gSharp = try #require(keyboard.key(for: 68))
        let a = try #require(keyboard.key(for: 69))
        #expect(abs(gSharp.midX - a.x) < 1e-9) // centred
    }

    @Test func hitTestingPrefersBlackKeysAtTheTop() throws {
        let keyboard = KeyboardLayout(range: 60...71, width: 700)
        let cSharp = try #require(keyboard.key(for: 61))
        #expect(keyboard.key(atX: cSharp.midX, y: 10, whiteKeyHeight: 100) == 61)
        #expect(keyboard.key(atX: cSharp.midX, y: 90, whiteKeyHeight: 100) != 61)
        #expect(keyboard.key(atX: 5, y: 90, whiteKeyHeight: 100) == 60)
        #expect(keyboard.key(atX: -1, y: 50, whiteKeyHeight: 100) == nil)
        #expect(keyboard.key(atX: 5, y: 101, whiteKeyHeight: 100) == nil)
        #expect(keyboard.whiteKeyHeight(maximum: 10) == 10)
    }

    @Test func displayRangeFollowsTheSongOrTheFullPiano() throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong("ode-to-joy.mid")) // 62…74
        #expect(KeyboardLayout.displayRange(for: song, transpose: 0, fullKeyboard: true) == 21...108)
        let range = KeyboardLayout.displayRange(for: song, transpose: 0, fullKeyboard: false)
        #expect(range.contains(62) && range.contains(74))
        #expect(Int(range.upperBound) - Int(range.lowerBound) >= 24)
        let shifted = KeyboardLayout.displayRange(for: song, transpose: 12, fullKeyboard: false)
        #expect(shifted.contains(86))
    }

    @Test func notesFallTowardsTheHitLine() throws {
        let song = TestSongs.song([TestSongs.N(pitch: 60, beat: 2, beats: 1)]) // starts at 1 s, lasts 0.5 s
        let keyboard = KeyboardLayout(range: 48...72, width: 750)
        let layout = FallingNotesLayout(keyboard: keyboard, hitLineY: 400, pointsPerSecond: 200)
        let rect = try #require(layout.rect(for: song.notes[0], now: 0))
        #expect(rect.y + rect.height == 200) // 1 s before the hit line
        #expect(rect.height == 100)
        let key = try #require(keyboard.key(for: 60))
        #expect(rect.x > key.x && rect.x + rect.width < key.maxX)
        #expect(layout.rect(for: song.notes[0], now: 1)?.y == 300)
        #expect(layout.visibleUntil(now: 0) == 2)
        let outOfRange = FallingNotesLayout(keyboard: KeyboardLayout(range: 72...84, width: 300), hitLineY: 400, pointsPerSecond: 200)
        #expect(outOfRange.rect(for: song.notes[0], now: 0) == nil)
        var tiny = layout
        tiny.minimumNoteHeight = 300
        #expect(tiny.rect(for: song.notes[0], now: 0)?.height == 300)
    }

    @Test func visibleIndicesCoverSoundingAndUpcomingNotes() throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong("fur-elise.mid"))
        let layout = FallingNotesLayout(keyboard: KeyboardLayout(range: 21...108, width: 1000), hitLineY: 500, pointsPerSecond: 250)
        let now = 30.0
        let range = layout.visibleNoteIndices(in: song, now: now, maxNoteDuration: song.longestNoteDuration)
        let expected = song.notes.indices.filter { i in
            let n = song.notes[i]
            return n.end > now && n.start <= layout.visibleUntil(now: now)
        }
        #expect(expected.allSatisfy { range.contains($0) })
        #expect(range.count < song.notes.count / 4)
        let measures = layout.visibleMeasureIndices(in: song, now: now)
        #expect(measures.allSatisfy { song.measures[$0].start >= now && song.measures[$0].start <= layout.visibleUntil(now: now) })
        #expect(!measures.isEmpty)
    }

    @Test func labelsFollowTheKeyAndTransposition() throws {
        let song = try MIDISongBuilder.song(from: Fixtures.builtinSong("gymnopedie-no1.mid")) // D major
        let labels = NoteLabels.labels(for: song, transpose: 0, style: .solfege)
        #expect(labels.count == song.notes.count)
        let fSharpIndex = try #require(song.notes.firstIndex { $0.pitch % 12 == 6 })
        #expect(labels[fSharpIndex] == "Fa♯")
        let flatKey = NoteLabels.labels(for: song, transpose: 0, style: .letters, forcedKey: KeySignature(fifths: -6))
        #expect(flatKey[fSharpIndex] == "G♭")
        let up = NoteLabels.labels(for: song, transpose: 1, style: .letters)
        #expect(up[fSharpIndex] == "G") // D major + 1 = E♭ major: F♯ + 1 = G
    }

    @Test func pressedKeysTracksHeldNotes() {
        let keys = PressedKeys()
        keys.apply(InputEvent(kind: .noteOn(pitch: 60, velocity: 80), time: 1))
        keys.apply(InputEvent(kind: .noteOn(pitch: 64, velocity: 80), time: 2))
        keys.apply(InputEvent(kind: .sustain(isDown: true), time: 2))
        keys.apply(InputEvent(kind: .noteOff(pitch: 60), time: 3))
        #expect(keys.current == [64: 2])
        keys.releaseAll()
        #expect(keys.current.isEmpty)
    }
}

@Suite("Live notes")
struct LiveNoteRecorderTests {
    @Test func recordsHeldAndReleasedNotesThenForgetsThem() {
        let recorder = LiveNoteRecorder(memory: 5)
        recorder.apply(InputEvent(kind: .noteOn(pitch: 60, velocity: 80), time: 10))
        recorder.apply(InputEvent(kind: .noteOn(pitch: 64, velocity: 80), time: 11))
        recorder.apply(InputEvent(kind: .noteOff(pitch: 60), time: 12))
        recorder.apply(InputEvent(kind: .noteOff(pitch: 70), time: 12)) // never pressed: ignored
        let notes = recorder.notes(at: 12)
        #expect(notes == [LiveNote(pitch: 60, start: 10, end: 12), LiveNote(pitch: 64, start: 11, end: nil)])
        #expect(recorder.notes(at: 20).map(\.pitch) == [64]) // the held note stays
        recorder.apply(InputEvent(kind: .noteOn(pitch: 72, velocity: 80), time: 30))
        #expect(recorder.notes(at: 30).map(\.pitch) == [64, 72])
        recorder.clear()
        #expect(recorder.notes(at: 30).isEmpty)
    }
}

@Suite("Full-page score layout")
struct PageLayoutTests {
    // Eight 4/4 measures at 120 bpm: 2 s each.
    let song = TestSongs.song((0..<32).map { TestSongs.N(pitch: 60, beat: Double($0)) })

    @Test func breaksMeasuresIntoJustifiedLines() {
        // 2 s × 50 pt/s = 100 pt per measure: three measures fit in 320 pt.
        let layout = PageLayout(measures: song.measures, width: 320, pointsPerSecond: 50, minimumMeasureWidth: 40)
        #expect(layout.systems.map(\.measures) == [0..<3, 3..<6, 6..<8])
        #expect(abs(layout.systems[0].edges.last! - 1) < 1e-9)
        #expect(abs(layout.systems[0].edges[1] - 1.0 / 3) < 1e-9)
        // The last line (200 of 320 pt) is not stretched.
        #expect(abs(layout.systems[2].edges.last! - 200.0 / 320) < 1e-9)
    }

    @Test func mapsTimesToPositionsAndBack() {
        let layout = PageLayout(measures: song.measures, width: 320, pointsPerSecond: 50, minimumMeasureWidth: 40)
        let line = layout.systems[1]
        #expect(layout.systemIndex(at: 7) == 1)
        #expect(abs(line.position(of: 9) - 0.5) < 1e-9) // middle of the middle measure
        #expect(abs(line.time(at: 0.5) - 9) < 1e-9)
        #expect(layout.systemIndex(at: 0) == 0)
        #expect(layout.systemIndex(at: 100) == 2)
    }

    @Test func aMeasureWiderThanTheLineGetsItsOwnLine() {
        let layout = PageLayout(measures: song.measures, width: 80, pointsPerSecond: 50, minimumMeasureWidth: 40)
        #expect(layout.systems.count == 8)
        #expect(layout.systems.allSatisfy { abs($0.edges.last! - 1) < 1e-9 })
    }
}
