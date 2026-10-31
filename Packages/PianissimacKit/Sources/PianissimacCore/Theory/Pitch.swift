import Foundation

/// Diatonic note letter. Raw value is the index from C.
public enum Step: Int, Sendable, Codable, CaseIterable {
    case c = 0, d, e, f, g, a, b

    /// Pitch class of the natural note.
    public var naturalPitchClass: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }

    public init?(letter: String) {
        switch letter.uppercased() {
        case "C": self = .c
        case "D": self = .d
        case "E": self = .e
        case "F": self = .f
        case "G": self = .g
        case "A": self = .a
        case "B": self = .b
        default: return nil
        }
    }

    public var letter: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
}

public enum Accidental: Int, Sendable, Codable, CaseIterable {
    case doubleFlat = -2, flat = -1, natural = 0, sharp = 1, doubleSharp = 2

    public init?(alter: Int) {
        self.init(rawValue: alter)
    }

    public var alter: Int { rawValue }

    public var symbol: String {
        switch self {
        case .doubleFlat: "𝄫"
        case .flat: "♭"
        case .natural: "♮"
        case .sharp: "♯"
        case .doubleSharp: "𝄪"
        }
    }
}

/// A pitch with its written spelling (C♯4 and D♭4 are different spellings of MIDI 61).
public struct SpelledPitch: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public var step: Step
    /// Chromatic alteration in semitones (−2…2).
    public var alter: Int
    /// Scientific octave: MIDI 60 is C4.
    public var octave: Int

    public init(step: Step, alter: Int, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }

    public var midiPitch: Int { (octave + 1) * 12 + step.naturalPitchClass + alter }

    /// Position on the staff counted in diatonic steps from C0 (one step = one line or space).
    public var diatonicIndex: Int { octave * 7 + step.rawValue }

    public var description: String {
        step.letter + (Accidental(alter: alter).map { $0 == .natural ? "" : $0.symbol } ?? "") + String(octave)
    }
}

public enum PianoKeys {
    public static let lowest: UInt8 = 21 // A0
    public static let highest: UInt8 = 108 // C8
    public static let middleC: UInt8 = 60

    public static func isBlack(_ pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
    }

    public static func isBlack(_ pitch: UInt8) -> Bool { isBlack(Int(pitch)) }

    /// Scientific octave of a MIDI pitch, ignoring spelling (60 → 4).
    public static func octave(of pitch: Int) -> Int {
        Int((Double(pitch) / 12).rounded(.down)) - 1
    }

    /// Transposes and clamps to the MIDI range.
    public static func transpose(_ pitch: UInt8, by semitones: Int) -> UInt8 {
        UInt8(clamping: min(127, max(0, Int(pitch) + semitones)))
    }
}
