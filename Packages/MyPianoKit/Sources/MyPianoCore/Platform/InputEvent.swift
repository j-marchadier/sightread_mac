import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Something the player did on a keyboard (MIDI, computer keys or mouse).
public struct InputEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case noteOn(pitch: UInt8, velocity: UInt8)
        case noteOff(pitch: UInt8)
        case sustain(isDown: Bool)
    }

    public var kind: Kind
    /// Host time in seconds (see ``HostTime``) at which the event happened.
    public var time: TimeInterval
    /// MIDI channel (0–15), when the event came from MIDI.
    public var channel: UInt8?

    public init(kind: Kind, time: TimeInterval, channel: UInt8? = nil) {
        self.kind = kind
        self.time = time
        self.channel = channel
    }
}

/// Plays piano sounds. Implementations must accept calls from any thread.
public protocol NoteOutput: AnyObject, Sendable {
    func noteOn(_ pitch: UInt8, velocity: UInt8)
    func noteOff(_ pitch: UInt8)
    func setSustain(_ isDown: Bool)
    func allNotesOff()
}

/// The machine's monotonic clock, shared by CoreAudio and CoreMIDI timestamps on macOS.
public enum HostTime {
    #if canImport(Darwin)
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Current host time in seconds.
    public static var now: TimeInterval { seconds(fromHostTicks: mach_absolute_time()) }

    /// Converts host ticks (`mach_absolute_time`, `MIDITimeStamp`, `AVAudioTime.hostTime`) to seconds.
    public static func seconds(fromHostTicks ticks: UInt64) -> TimeInterval {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    public static func hostTicks(fromSeconds seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer))
    }
    #else
    public static var now: TimeInterval { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    public static func seconds(fromHostTicks ticks: UInt64) -> TimeInterval { Double(ticks) / 1_000_000_000 }

    public static func hostTicks(fromSeconds seconds: TimeInterval) -> UInt64 { UInt64(max(0, seconds) * 1_000_000_000) }
    #endif
}
