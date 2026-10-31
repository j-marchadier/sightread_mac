import Foundation

/// A note as the score editor stores it: placed in ticks, its times are derived from the song's tempo map.
public struct EditedNote: Sendable, Codable, Equatable, Hashable {
    public var pitch: UInt8
    public var velocity: UInt8
    public var track: Int
    public var startTick: Int
    public var durationTicks: Int
    /// Staff given by the score file (1 = upper), if any.
    public var staff: Int?
    /// Finger written on the note (1 = thumb … 5 = little finger), if any.
    public var finger: UInt8?

    public init(pitch: UInt8, velocity: UInt8 = 80, track: Int, startTick: Int, durationTicks: Int,
                staff: Int? = nil, finger: UInt8? = nil) {
        self.pitch = pitch
        self.velocity = velocity
        self.track = track
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.staff = staff
        self.finger = finger
    }

    public init(_ note: Note) {
        self.init(pitch: note.pitch, velocity: note.velocity, track: note.track, startTick: note.startTick,
                  durationTicks: note.durationTicks, staff: note.staff, finger: note.finger)
    }

    public var endTick: Int { startTick + durationTicks }

    /// The order of ``Song/notes``: by start, then pitch, then track. Sorting edited notes this way
    /// gives each one the id it gets in the edited song.
    public static func isOrderedBefore(_ lhs: EditedNote, _ rhs: EditedNote) -> Bool {
        (lhs.startTick, lhs.pitch, lhs.track, lhs.durationTicks) < (rhs.startTick, rhs.pitch, rhs.track, rhs.durationTicks)
    }
}

/// The notes of a song as changed in the score editor. Stored beside the library, so the original
/// file (a built-in song, or the imported copy) is never modified and can be restored.
public struct SongEdit: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var notes: [EditedNote]
    public var editedAt: Date

    public init(notes: [EditedNote], editedAt: Date = Date()) {
        version = Self.currentVersion
        self.notes = notes
        self.editedAt = editedAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SongEdit {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SongEdit.self, from: data)
    }
}

extension Song {
    public var editedNotes: [EditedNote] { notes.map(EditedNote.init) }

    /// The song with its notes replaced.
    ///
    /// Notes are sorted (see ``EditedNote/isOrderedBefore(_:_:)``) and renumbered, their times
    /// recomputed from the tempo map, and measures added when notes go past the last one. Written
    /// notation from a MusicXML file refers to the original notes, so it is dropped once they change:
    /// the score is then quantized from the notes, like a MIDI file's.
    public func replacingNotes(_ edited: [EditedNote]) -> Song {
        let sorted = edited
            .map { note -> EditedNote in
                var note = note
                note.startTick = max(0, note.startTick)
                note.durationTicks = max(1, note.durationTicks)
                note.pitch = min(127, note.pitch)
                if let finger = note.finger, !(1...5).contains(finger) { note.finger = nil }
                return note
            }
            .sorted(by: EditedNote.isOrderedBefore)
        if sorted == notes.map(EditedNote.init) { return self }

        var song = self
        song.notation = nil
        let endTick = sorted.map(\.endTick).max() ?? 0
        if endTick > (measures.last?.endTick ?? 0) {
            song.measures = Self.measures(extending: measures, to: endTick, timeSignatures: timeSignatures, tempoMap: tempoMap)
        }
        song.notes = sorted.enumerated().map { id, note in
            let start = tempoMap.seconds(atTick: note.startTick)
            return Note(
                id: id, pitch: note.pitch, velocity: note.velocity, track: note.track,
                startTick: note.startTick, durationTicks: note.durationTicks,
                start: start, duration: tempoMap.seconds(atTick: note.endTick) - start,
                measureIndex: song.measureIndex(atTick: note.startTick), staff: note.staff, finger: note.finger
            )
        }
        return song
    }

    /// Adds measures of the last time signature until `endTick` is covered.
    private static func measures(extending measures: [Measure], to endTick: Int, timeSignatures: [TimeSignatureChange],
                                 tempoMap: TempoMap) -> [Measure] {
        guard let last = measures.last else {
            return MeasureBuilder.measures(timeSignatures: timeSignatures, endTick: endTick, tempoMap: tempoMap)
        }
        var result = measures
        let signature = (timeSignatures.last { $0.tick <= last.startTick } ?? timeSignatures.first)?.signature ?? .common
        let length = max(1, signature.ticksPerMeasure(ticksPerQuarter: tempoMap.ticksPerQuarter))
        var start = last.endTick
        var number = last.number
        while start < endTick {
            number += 1
            result.append(Measure(number: number, startTick: start, endTick: start + length,
                                  start: tempoMap.seconds(atTick: start), end: tempoMap.seconds(atTick: start + length)))
            start += length
        }
        return result
    }
}

extension StaffGeometry {
    /// The pitch written at `step` on `clef` without accidental, so with the key's alteration.
    public static func pitch(atStep step: Int, clef: Clef, key: KeySignature?) -> SpelledPitch {
        let index = clef.topLineIndex - step
        let octave = Int((Double(index) / 7).rounded(.down))
        let letter = Step(rawValue: index - octave * 7) ?? .c
        return SpelledPitch(step: letter, alter: key?.alteration(for: letter) ?? 0, octave: octave)
    }
}

extension NoteValue {
    /// Length in ticks, with `dots` augmentation dots.
    public func ticks(ticksPerQuarter: Int, dots: Int = 0) -> Int {
        var length = Double(ticksPerQuarter) * quarters
        var added = length
        for _ in 0..<dots {
            added /= 2
            length += added
        }
        return Int(length.rounded())
    }
}
