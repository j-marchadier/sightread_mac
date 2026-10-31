import Foundation

public enum Clef: String, Sendable, Codable, CaseIterable {
    case treble
    case bass

    /// Diatonic index (see ``SpelledPitch/diatonicIndex``) of the top staff line: F5 or A3.
    public var topLineIndex: Int {
        switch self {
        case .treble: 5 * 7 + Step.f.rawValue
        case .bass: 3 * 7 + Step.a.rawValue
        }
    }

    /// Step of the line the clef symbol is drawn on (G4 line for the G clef, F3 line for the F clef).
    public var symbolStep: Int {
        switch self {
        case .treble: StaffGeometry.step(of: SpelledPitch(step: .g, alter: 0, octave: 4), clef: .treble)
        case .bass: StaffGeometry.step(of: SpelledPitch(step: .f, alter: 0, octave: 3), clef: .bass)
        }
    }

    /// Staff for a note: by hand when known, otherwise middle C and above go to the treble staff.
    public static func forNote(hand: Hand?, pitch: Int) -> Clef {
        switch hand {
        case .right: .treble
        case .left: .bass
        case nil: pitch >= Int(PianoKeys.middleC) ? .treble : .bass
        }
    }
}

/// Vertical positions on a five-line staff, counted in steps (half staff spaces) downward from
/// the top line: lines are at even steps 0, 2, 4, 6, 8; step 4 is the middle line.
public enum StaffGeometry {
    public static let middleLineStep = 4
    public static let bottomLineStep = 8

    public static func step(of pitch: SpelledPitch, clef: Clef) -> Int {
        clef.topLineIndex - pitch.diatonicIndex
    }

    /// Steps of the ledger lines a note at `step` needs (outside the staff, even steps only).
    public static func ledgerLineSteps(for step: Int) -> [Int] {
        if step <= -2 {
            return Array(stride(from: -2, through: step % 2 == 0 ? step : step + 1, by: -2))
        }
        if step >= 10 {
            return Array(stride(from: 10, through: step % 2 == 0 ? step : step - 1, by: 2))
        }
        return []
    }

    private static let sharpPositions: [SpelledPitch] = [
        .init(step: .f, alter: 0, octave: 5), .init(step: .c, alter: 0, octave: 5), .init(step: .g, alter: 0, octave: 5),
        .init(step: .d, alter: 0, octave: 5), .init(step: .a, alter: 0, octave: 4), .init(step: .e, alter: 0, octave: 5),
        .init(step: .b, alter: 0, octave: 4),
    ]
    private static let flatPositions: [SpelledPitch] = [
        .init(step: .b, alter: 0, octave: 4), .init(step: .e, alter: 0, octave: 5), .init(step: .a, alter: 0, octave: 4),
        .init(step: .d, alter: 0, octave: 5), .init(step: .g, alter: 0, octave: 4), .init(step: .c, alter: 0, octave: 5),
        .init(step: .f, alter: 0, octave: 4),
    ]

    /// Steps of the accidentals of a key signature, in writing order. The bass staff uses the same
    /// shape two octaves lower, which lands two steps lower on the staff.
    public static func keySignatureSteps(_ key: KeySignature, clef: Clef) -> [Int] {
        let positions = key.usesFlats ? flatPositions : sharpPositions
        let count = abs(key.fifths)
        return positions.prefix(count).map { step(of: $0, clef: .treble) + (clef == .bass ? 2 : 0) }
    }
}
