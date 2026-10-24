import Foundation

/// The simplified score: one note head per playable note, placed on the grand staff with a tail
/// showing its length instead of a rhythmic value. Accidentals follow the key and the measure.
public struct SimplifiedScore: Sendable {
    public struct Head: Sendable, Equatable {
        public let noteID: Int
        public let clef: Clef
        public let step: Int
        public let pitch: SpelledPitch
        public let accidental: Accidental?
        public let start: TimeInterval
        public let end: TimeInterval
    }

    /// Note heads sorted by start time.
    public let heads: [Head]

    /// - Parameters:
    ///   - hands: Hand of each note (index = note id). Accompaniment (`nil`) is left out when any
    ///     note has a hand; otherwise every note is shown, split at middle C.
    ///   - forcedKey: Key chosen by the player instead of the file's.
    public init(song: Song, hands: [Hand?], transpose: Int, forcedKey: KeySignature? = nil) {
        let anyHand = hands.contains { $0 != nil }
        var states: [Clef: (measure: Int, state: MeasureAccidentalState)] = [:]
        var heads: [Head] = []
        for note in song.notes {
            let hand = hands.indices.contains(note.id) ? hands[note.id] : nil
            if anyHand && hand == nil { continue }
            let pitch = Int(PianoKeys.transpose(note.pitch, by: transpose))
            let key = (forcedKey ?? song.keySignature(atTick: note.startTick))?.transposed(by: transpose)
            let spelled = Speller.spell(pitch, in: key)
            let clef = Clef.forNote(hand: hand, pitch: pitch)
            if states[clef]?.measure != note.measureIndex || states[clef]?.state.key != key {
                states[clef] = (note.measureIndex, MeasureAccidentalState(key: key))
            }
            let accidental = states[clef]!.state.accidental(for: spelled)
            heads.append(Head(
                noteID: note.id, clef: clef, step: StaffGeometry.step(of: spelled, clef: clef), pitch: spelled,
                accidental: accidental, start: note.start, end: note.end
            ))
        }
        self.heads = heads
    }
}
