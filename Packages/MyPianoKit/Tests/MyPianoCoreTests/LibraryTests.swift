import Foundation
import Testing
@testable import MyPianoCore

@Suite("Library")
struct LibraryTests {
    private func song(_ id: String, title: String, composer: String? = nil, source: SongSource = .builtin, duration: TimeInterval = 60, difficulty: Int = 2) -> LibrarySong {
        LibrarySong(id: id, title: title, composer: composer, source: source, fileName: "\(id).mid", duration: duration, difficulty: difficulty)
    }

    private func summary(accuracy hits: Int, of total: Int, mode: PracticeMode = .learn, at date: Date) -> SessionSummary {
        var stats = PracticeStats()
        for _ in 0..<hits { stats.recordHit(.perfect) }
        for _ in hits..<total { stats.recordMiss() }
        var settings = PracticeSettings()
        settings.mode = mode
        return SessionSummary(startedAt: date, practiceSeconds: 60, settings: settings, stats: stats, completion: 1)
    }

    @Test func searchSortAndCategories() {
        var database = LibraryDatabase()
        database.upsert(song("a", title: "Für Elise", composer: "Ludwig van Beethoven", duration: 148, difficulty: 3))
        database.upsert(song("b", title: "Ode à la joie", composer: "Ludwig van Beethoven", duration: 31, difficulty: 1))
        database.upsert(song("c", title: "Clair de lune", composer: "Claude Debussy", duration: 245, difficulty: 5))
        database.upsert(song("d", title: "Ma chanson", source: .imported, duration: 90, difficulty: 2))
        #expect(database.songs(in: .all).map(\.id) == ["c", "a", "d", "b"])
        #expect(database.songs(in: .all, sortedBy: .duration).map(\.id) == ["b", "d", "a", "c"])
        #expect(database.songs(in: .all, sortedBy: .difficulty, ascending: false).first?.id == "c")
        #expect(database.songs(in: .all, sortedBy: .composer).map(\.id) == ["d", "c", "a", "b"])
        #expect(database.songs(in: .all, matching: "fur").map(\.id) == ["a"]) // accents ignored
        #expect(database.songs(in: .all, matching: "beethoven").count == 2)
        #expect(database.songs(in: .imported).map(\.id) == ["d"])
        database.update("b") { $0.isFavorite = true }
        #expect(database.songs(in: .favorites).map(\.id) == ["b"])
        #expect(database.songs(in: .recent).isEmpty)
    }

    @Test func historyAndProgress() {
        var database = LibraryDatabase()
        database.upsert(song("a", title: "Für Elise"))
        database.upsert(song("b", title: "Ode"))
        let day = Date(timeIntervalSince1970: 1_000_000)
        database.record(summary(accuracy: 6, of: 10, at: day), for: "a")
        database.record(summary(accuracy: 9, of: 10, at: day.addingTimeInterval(100)), for: "a")
        database.record(summary(accuracy: 0, of: 10, mode: .listen, at: day.addingTimeInterval(200)), for: "a")
        database.record(summary(accuracy: 5, of: 10, at: day.addingTimeInterval(50)), for: "b")
        let progress = database.progress(for: "a")
        #expect(progress.sessions == 3)
        #expect(progress.bestAccuracy == 0.9)
        #expect(progress.lastAccuracy == 0.9) // listening sessions are not judged
        #expect(progress.practiceSeconds == 180)
        #expect(database.song("a")?.lastPlayed == day.addingTimeInterval(200))
        #expect(database.songs(in: .recent).map(\.id) == ["a", "b"])
        database.remove("a")
        #expect(database.records.count == 1 && database.song("a") == nil)
    }

    @Test func upsertKeepsWhatThePlayerDid() {
        var database = LibraryDatabase()
        database.upsert(song("a", title: "Old title"))
        database.update("a") {
            $0.isFavorite = true
            $0.settings = PracticeSettings()
        }
        database.upsert(song("a", title: "New title"))
        #expect(database.song("a")?.title == "New title")
        #expect(database.song("a")?.isFavorite == true)
        #expect(database.song("a")?.settings != nil)
        #expect(database.songs.count == 1)
    }

    @Test func savesAndLoadsAtomically() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryFileStore(url: folder.appendingPathComponent("Library/library.json"))
        #expect(try store.load() == LibraryDatabase())
        var database = LibraryDatabase()
        var entry = song("a", title: "Für Elise")
        var settings = PracticeSettings()
        settings.mode = .wait
        settings.loop = LoopRange(firstMeasure: 2, lastMeasure: 5)
        entry.settings = settings
        database.upsert(entry)
        database.record(summary(accuracy: 3, of: 4, at: Date(timeIntervalSince1970: 1_700_000_000)), for: "a")
        try store.save(database)
        #expect(try store.load() == database)
    }

    @Test("Settings saved by an older version still load")
    func settingsDecodeWithMissingKeys() throws {
        let json = #"{"mode":"wait","speed":0.5,"hands":["left"]}"#
        let settings = try JSONDecoder().decode(PracticeSettings.self, from: Data(json.utf8))
        #expect(settings.mode == .wait && settings.speed == 0.5 && settings.hands == [.left])
        #expect(settings.waitTolerance == 0.25 && settings.countdownEnabled)
        let roundTrip = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip == settings)
    }

    @Test func difficultyRanksTheBuiltinSongs() throws {
        func rating(_ file: String) throws -> Int {
            try DifficultyEstimator.rating(for: MIDISongBuilder.song(from: Fixtures.builtinSong(file)))
        }
        let twinkle = try rating("twinkle-twinkle-little-star.mid")
        let elise = try rating("fur-elise.mid")
        let rondo = try rating("rondo-alla-turca.mid")
        #expect(twinkle <= 2)
        #expect(twinkle < elise)
        #expect(elise <= rondo)
        #expect(rondo >= 4)
        let empty = Song(tracks: [], notes: [], measures: [], tempoMap: TempoMap(ticksPerQuarter: 480), timeSignatures: [], keySignatures: [])
        #expect(DifficultyEstimator.rating(for: empty) == 1)
    }
}

@Suite("Exercises")
struct ExerciseTests {
    @Test func noteReadingStaysOnTheStaffAndInTheKey() {
        let exercise = NoteReadingExercise(staff: .treble, key: KeySignature(fifths: 2)!, noteCount: 24)
        let song = exercise.makeSong(seed: 42)
        #expect(song.notes.count == 24)
        #expect(song.notes.allSatisfy { NoteReadingExercise.trebleRange.contains(Int($0.pitch)) })
        let scale = Set(KeySignature(fifths: 2)!.scalePitchClasses)
        #expect(song.notes.allSatisfy { scale.contains(Int($0.pitch) % 12) })
        #expect(zip(song.notes, song.notes.dropFirst()).allSatisfy { $0.pitch != $1.pitch })
        #expect(song.measures.count == 6)
        #expect(song.primaryKeySignature?.fifths == 2)
        #expect(exercise.makeSong(seed: 42) == song) // reproducible
        #expect(exercise.makeSong(seed: 43) != song)
    }

    @Test func noteReadingOnBothStavesUsesBothHands() {
        let song = NoteReadingExercise(staff: .grand, noteCount: 40).makeSong(seed: 7)
        let hands = song.notes.map { ExerciseSongBuilder.hands.hand(for: $0) }
        #expect(hands.contains(.left) && hands.contains(.right))
        for note in song.notes {
            let range = ExerciseSongBuilder.hands.hand(for: note) == .right ? NoteReadingExercise.trebleRange : NoteReadingExercise.bassRange
            #expect(range.contains(Int(note.pitch)))
        }
    }

    @Test("Phrases fill their measures at every level", arguments: 0...3)
    func phrases(level: Int) {
        for staff in ExerciseStaff.allCases {
            let exercise = PhraseExercise(staff: staff, level: level, key: KeySignature(fifths: -1)!, measures: 8)
            let song = exercise.makeSong(seed: UInt64(level * 10 + 1))
            #expect(song.measures.count == 8)
            let scale = Set(KeySignature(fifths: -1)!.scalePitchClasses)
            #expect(song.notes.allSatisfy { scale.contains(Int($0.pitch) % 12) })
            for hand in [Hand.right, .left] {
                let notes = song.notes.filter { ExerciseSongBuilder.hands.hand(for: $0) == hand }
                let expectsHand = staff == .grand || (staff == .treble) == (hand == .right)
                #expect(notes.isEmpty != expectsHand)
                guard expectsHand else { continue }
                for measure in song.measures {
                    let ticks = notes.filter { $0.measureIndex == song.measures.firstIndex(of: measure)! }.reduce(0) { $0 + $1.durationTicks }
                    #expect(ticks == measure.ticks, "level \(level) \(hand) measure \(measure.number)")
                }
            }
            let last = song.notes.filter { ExerciseSongBuilder.hands.hand(for: $0) == .right }.last
            if let last { #expect(Int(last.pitch) % 12 == KeySignature(fifths: -1)!.tonicPitchClass) } // ends on the tonic
            let assignment = ExerciseSongBuilder.hands
            #expect(RhythmicScore(song: song, hands: song.notes.map { assignment.hand(for: $0) }, transpose: 0).quality == 1)
        }
    }
}

@Suite("Watched folder")
struct WatchedFolderSyncTests {
    private func song(_ id: String, path: String?, hash: String, source: SongSource = .watched) -> LibrarySong {
        var song = LibrarySong(id: id, title: id, source: source, fileName: id + ".mid", duration: 10, difficulty: 1, contentHash: hash)
        song.sourcePath = path
        return song
    }

    @Test func addsNewFilesButNotDuplicatesOrIgnoredOnes() {
        let library = [song("a", path: "/w/a.mid", hash: "A"), song("b", path: nil, hash: "B", source: .imported)]
        let found = [
            WatchedFolderSync.FoundFile(path: "/w/a.mid", hash: "A"),
            .init(path: "/w/b-copy.mid", hash: "B"), // already imported by hand
            .init(path: "/w/c.mid", hash: "C"),
            .init(path: "/w/c2.mid", hash: "C"), // same content twice
            .init(path: "/w/d.mid", hash: "D"), // removed by the player earlier
        ]
        #expect(WatchedFolderSync.plan(found: found, library: library, ignoring: ["D"]) == [.add(path: "/w/c.mid")])
    }

    @Test func followsRenamesAndRemovesMissingFiles() {
        let library = [song("a", path: "/w/a.mid", hash: "A"), song("b", path: "/w/b.mid", hash: "B")]
        let found = [WatchedFolderSync.FoundFile(path: "/w/sub/a renamed.mid", hash: "A")]
        #expect(WatchedFolderSync.plan(found: found, library: library) == [.move(id: "a", to: "/w/sub/a renamed.mid"), .remove(id: "b")])
    }

    @Test func anEditedFileIsReplaced() {
        let library = [song("a", path: "/w/a.mid", hash: "A")]
        let found = [WatchedFolderSync.FoundFile(path: "/w/a.mid", hash: "A2")]
        #expect(WatchedFolderSync.plan(found: found, library: library) == [.remove(id: "a"), .add(path: "/w/a.mid")])
    }
}
