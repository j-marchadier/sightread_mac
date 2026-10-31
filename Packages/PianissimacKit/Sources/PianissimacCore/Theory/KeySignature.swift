import Foundation

/// A major key signature, identified by its position on the circle of fifths
/// (−7 = seven flats … 0 = no accidental … +7 = seven sharps).
/// Minor keys are represented by their relative major, which shares the signature.
public struct KeySignature: Sendable, Equatable, Hashable, Codable, CaseIterable, CustomStringConvertible {
    public let fifths: Int

    public init?(fifths: Int) {
        guard (-7...7).contains(fifths) else { return nil }
        self.fifths = fifths
    }

    private init(unchecked fifths: Int) {
        self.fifths = fifths
    }

    public static let cMajor = KeySignature(unchecked: 0)

    /// All 15 signatures, from seven flats to seven sharps.
    public static let allCases: [KeySignature] = (-7...7).map { KeySignature(unchecked: $0) }

    public static let sharpOrder: [Step] = [.f, .c, .g, .d, .a, .e, .b]
    public static let flatOrder: [Step] = [.b, .e, .a, .d, .g, .c, .f]

    public var usesSharps: Bool { fifths > 0 }
    public var usesFlats: Bool { fifths < 0 }

    /// Altered steps in the order they are written on the staff.
    public var alteredSteps: [Step] {
        fifths >= 0 ? Array(Self.sharpOrder.prefix(fifths)) : Array(Self.flatOrder.prefix(-fifths))
    }

    /// Alteration the signature applies to a step (+1, −1 or 0).
    public func alteration(for step: Step) -> Int {
        alteredSteps.contains(step) ? (fifths > 0 ? 1 : -1) : 0
    }

    /// Tonic of the major key.
    public var tonic: SpelledPitch {
        let steps: [Step] = [.c, .g, .d, .a, .e, .b, .f, .c, .g, .d, .a, .e, .b, .f, .c]
        let step = steps[fifths + 7]
        return SpelledPitch(step: step, alter: alteration(for: step), octave: 4)
    }

    public var tonicPitchClass: Int { ((fifths * 7) % 12 + 12) % 12 }

    /// Name of the major key in English letters, e.g. "Bb", "F#", "C".
    public var name: String {
        let tonic = tonic
        return tonic.step.letter + (tonic.alter > 0 ? "#" : tonic.alter < 0 ? "b" : "")
    }

    public var description: String { name }

    /// Pitch classes of the major scale, starting on the tonic.
    public var scalePitchClasses: [Int] {
        [0, 2, 4, 5, 7, 9, 11].map { ($0 + tonicPitchClass) % 12 }
    }

    /// Moves the tonic by `semitones`, keeping the sharp or flat flavour when both spellings exist
    /// (C♯/D♭, F♯/G♭, B/C♭).
    public func transposed(by semitones: Int) -> KeySignature {
        guard semitones % 12 != 0 else { return self }
        let target = ((tonicPitchClass + semitones) % 12 + 12) % 12
        let options = KeySignature.allCases.filter { $0.tonicPitchClass == target }
        if options.count == 1 { return options[0] }
        if usesSharps, let sharp = options.first(where: { $0.fifths > 0 }) { return sharp }
        if usesFlats, let flat = options.first(where: { $0.fifths < 0 }) { return flat }
        // From C major, ambiguous targets fall back on C♯, F♯ and B (rather than D♭, G♭ and C♭).
        let defaults = [1: 7, 6: 6, 11: 5]
        return KeySignature(unchecked: defaults[target] ?? options[0].fifths)
    }
}
