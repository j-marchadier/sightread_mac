import Foundation

/// Engraving information read from score files (MusicXML).
///
/// Playable ``Note``s merge tied notes and unroll repeats; the score display instead needs every
/// written note head and rest as printed. Each ``NotatedEvent`` is one written chord or rest
/// placed on the unrolled timeline, so it can be drawn in sync with playback.
public struct NotationHints: Sendable, Equatable {
    public var events: [NotatedEvent]
    public init(events: [NotatedEvent] = []) {
        self.events = events
    }
}

public enum NoteValue: Int, Sendable, Codable, CaseIterable, Comparable {
    case breve = 0, whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth, hundredTwentyEighth

    /// MusicXML `<type>` names.
    public init?(musicXMLName: String) {
        switch musicXMLName {
        case "breve": self = .breve
        case "whole": self = .whole
        case "half": self = .half
        case "quarter": self = .quarter
        case "eighth": self = .eighth
        case "16th": self = .sixteenth
        case "32nd": self = .thirtySecond
        case "64th": self = .sixtyFourth
        case "128th": self = .hundredTwentyEighth
        default: return nil
        }
    }

    /// Length in quarter notes, without dots.
    public var quarters: Double {
        pow(2, Double(NoteValue.quarter.rawValue - rawValue))
    }

    /// Number of flags or beams (0 for quarter and longer).
    public var beamCount: Int { max(0, rawValue - NoteValue.quarter.rawValue) }

    public static func < (lhs: NoteValue, rhs: NoteValue) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum BeamState: String, Sendable, Codable {
    case begin, `continue`, end, forwardHook = "forward hook", backwardHook = "backward hook"
}

public struct WrittenPitch: Sendable, Equatable, Codable {
    public var spelling: SpelledPitch
    /// Accidental explicitly printed in the file, if any.
    public var printedAccidental: Accidental?
    public var tieStart: Bool
    public var tieStop: Bool
    /// Playable note this head belongs to (the first note of a tie chain).
    public var noteID: Int?

    public init(spelling: SpelledPitch, printedAccidental: Accidental? = nil, tieStart: Bool = false, tieStop: Bool = false, noteID: Int? = nil) {
        self.spelling = spelling
        self.printedAccidental = printedAccidental
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.noteID = noteID
    }
}

public struct NotatedEvent: Sendable, Equatable {
    public var startTick: Int
    public var durationTicks: Int
    public var measureIndex: Int
    public var staff: Int
    public var voice: Int
    public var value: NoteValue?
    public var dots: Int
    /// Tuplet ratio as (actual notes, normal notes), e.g. (3, 2) for a triplet.
    public var tuplet: (actual: Int, normal: Int)?
    /// Empty for a rest.
    public var pitches: [WrittenPitch]
    /// Beam state per beam level (index 0 = eighth beam).
    public var beams: [BeamState]
    public var stemUp: Bool?
    public var track: Int

    public init(
        startTick: Int, durationTicks: Int, measureIndex: Int, staff: Int, voice: Int,
        value: NoteValue?, dots: Int = 0, tuplet: (actual: Int, normal: Int)? = nil,
        pitches: [WrittenPitch], beams: [BeamState] = [], stemUp: Bool? = nil, track: Int
    ) {
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.measureIndex = measureIndex
        self.staff = staff
        self.voice = voice
        self.value = value
        self.dots = dots
        self.tuplet = tuplet
        self.pitches = pitches
        self.beams = beams
        self.stemUp = stemUp
        self.track = track
    }

    public var isRest: Bool { pitches.isEmpty }

    public static func == (lhs: NotatedEvent, rhs: NotatedEvent) -> Bool {
        lhs.startTick == rhs.startTick && lhs.durationTicks == rhs.durationTicks && lhs.measureIndex == rhs.measureIndex
            && lhs.staff == rhs.staff && lhs.voice == rhs.voice && lhs.value == rhs.value && lhs.dots == rhs.dots
            && lhs.tuplet?.actual == rhs.tuplet?.actual && lhs.tuplet?.normal == rhs.tuplet?.normal
            && lhs.pitches == rhs.pitches && lhs.beams == rhs.beams && lhs.stemUp == rhs.stemUp && lhs.track == rhs.track
    }
}
