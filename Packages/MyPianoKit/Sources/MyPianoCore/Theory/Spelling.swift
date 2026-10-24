import Foundation

/// Chooses how to write a MIDI pitch in a given key.
public enum Speller {
    /// Spells `pitch` in `key`:
    /// 1. a note of the key's scale keeps the key's spelling (F♯ in G major, E♯ in F♯ major);
    /// 2. other notes use a natural when possible, otherwise a sharp in sharp keys (and C major
    ///    or unknown keys) or a flat in flat keys.
    public static func spell(_ pitch: Int, in key: KeySignature?) -> SpelledPitch {
        let pitchClass = ((pitch % 12) + 12) % 12
        var candidates: [(step: Step, alter: Int)] = []
        for step in Step.allCases {
            var alter = pitchClass - step.naturalPitchClass
            if alter > 6 { alter -= 12 }
            if alter < -6 { alter += 12 }
            if abs(alter) <= 1 { candidates.append((step, alter)) }
        }

        let chosen: (step: Step, alter: Int)
        if let key, let diatonic = candidates.first(where: { $0.alter == key.alteration(for: $0.step) }) {
            chosen = diatonic
        } else if let natural = candidates.first(where: { $0.alter == 0 }) {
            chosen = natural
        } else {
            let preferred = (key?.usesFlats ?? false) ? -1 : 1
            chosen = candidates.first { $0.alter == preferred } ?? candidates[0]
        }
        let octave = (pitch - chosen.step.naturalPitchClass - chosen.alter) / 12 - 1
        return SpelledPitch(step: chosen.step, alter: chosen.alter, octave: octave)
    }

    /// Accidental to print for `pitch` against the key alone (no measure memory):
    /// `nil` when the key signature already gives the right alteration.
    public static func accidentalAgainstKey(_ pitch: SpelledPitch, key: KeySignature?) -> Accidental? {
        let expected = key?.alteration(for: pitch.step) ?? 0
        return pitch.alter == expected ? nil : Accidental(alter: pitch.alter)
    }
}

/// Keeps track of accidentals already printed in a measure, so repeated notes are not re-marked
/// and naturals are printed when needed. Call ``reset()`` at each bar line.
public struct MeasureAccidentalState: Sendable {
    public let key: KeySignature?
    private var current: [Int: Int] = [:] // diatonic index → alteration in force

    public init(key: KeySignature?) {
        self.key = key
    }

    public mutating func reset() {
        current.removeAll()
    }

    /// Returns the accidental to print for `pitch` and records it.
    public mutating func accidental(for pitch: SpelledPitch) -> Accidental? {
        let inForce = current[pitch.diatonicIndex] ?? (key?.alteration(for: pitch.step) ?? 0)
        current[pitch.diatonicIndex] = pitch.alter
        return pitch.alter == inForce ? nil : Accidental(alter: pitch.alter)
    }
}
