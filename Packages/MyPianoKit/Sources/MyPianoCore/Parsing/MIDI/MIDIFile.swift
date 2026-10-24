import Foundation

/// Raw content of a Standard MIDI File, before interpretation.
public struct MIDIFile: Sendable, Equatable {
    public var format: Int
    public var ticksPerQuarter: Int
    public var tracks: [[MIDIEvent]]

    public init(format: Int, ticksPerQuarter: Int, tracks: [[MIDIEvent]]) {
        self.format = format
        self.ticksPerQuarter = ticksPerQuarter
        self.tracks = tracks
    }
}

public struct MIDIEvent: Sendable, Equatable {
    /// Absolute position in ticks from the start of the track.
    public var tick: Int
    public var kind: Kind

    public init(tick: Int, kind: Kind) {
        self.tick = tick
        self.kind = kind
    }

    public enum Kind: Sendable, Equatable {
        case noteOn(channel: UInt8, pitch: UInt8, velocity: UInt8)
        case noteOff(channel: UInt8, pitch: UInt8, velocity: UInt8)
        case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
        case programChange(channel: UInt8, program: UInt8)
        case otherChannelMessage(status: UInt8)
        case tempo(microsecondsPerQuarter: Int)
        case timeSignature(numerator: Int, denominator: Int)
        case keySignature(fifths: Int, isMinor: Bool)
        case trackName(String)
        case text(type: UInt8, String)
        case endOfTrack
        case otherMeta(type: UInt8)
        case sysex
    }
}

public enum MIDIFileError: Error, Equatable, Sendable {
    /// The data does not start with an `MThd` header.
    case notAMIDIFile
    /// SMPTE time division is not supported.
    case unsupportedTimeDivision
    /// Format 2 (independent sequences) is not supported.
    case unsupportedFormat(Int)
    /// The file ends before the header or the first track is complete.
    case truncated
    /// The file contains no track.
    case noTracks
}
