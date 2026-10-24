import Foundation

/// Names shown on notes, spelled in the key in force at each note (after transposition).
public enum NoteLabels {
    public static func labels(for song: Song, transpose: Int, style: NoteNamingStyle, forcedKey: KeySignature? = nil) -> [String] {
        song.notes.map { note in
            let key = (forcedKey ?? song.keySignature(atTick: note.startTick))?.transposed(by: transpose)
            let pitch = Int(PianoKeys.transpose(note.pitch, by: transpose))
            return style.name(of: Speller.spell(pitch, in: key))
        }
    }
}
