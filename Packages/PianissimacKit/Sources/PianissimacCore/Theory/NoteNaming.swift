import Foundation

/// How note names are displayed.
public enum NoteNamingStyle: String, Sendable, Codable, CaseIterable {
    /// Do, Ré, Mi, Fa, Sol, La, Si (fixed do).
    case solfege
    /// C, D, E, F, G, A, B.
    case letters

    public func name(of step: Step) -> String {
        switch self {
        case .solfege: ["Do", "Ré", "Mi", "Fa", "Sol", "La", "Si"][step.rawValue]
        case .letters: step.letter
        }
    }

    /// Name with its accidental, e.g. "Fa♯" or "F♯". Naturals are not shown.
    public func name(of pitch: SpelledPitch, includeOctave: Bool = false) -> String {
        var text = name(of: pitch.step)
        if pitch.alter != 0, let accidental = Accidental(alter: pitch.alter) {
            text += accidental.symbol
        }
        if includeOctave {
            text += String(pitch.octave)
        }
        return text
    }
}
