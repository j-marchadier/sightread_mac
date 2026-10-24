import Foundation

/// How the song reacts to the player.
public enum PracticeMode: String, Sendable, Codable, CaseIterable {
    /// The song plays on; notes of the active hands are judged.
    case learn
    /// The song stops on each note of the active hands until it is played.
    case wait
    /// The song plays for listening; nothing is judged.
    case listen
}

/// A loop over whole measures (indices into `Song.measures`, both included).
public struct LoopRange: Sendable, Equatable, Codable {
    public var firstMeasure: Int
    public var lastMeasure: Int

    public init(firstMeasure: Int, lastMeasure: Int) {
        self.firstMeasure = min(firstMeasure, lastMeasure)
        self.lastMeasure = max(firstMeasure, lastMeasure)
    }

    /// Song seconds covered by the loop, with measure indices clamped to the song.
    public func timeRange(in song: Song) -> ClosedRange<TimeInterval>? {
        guard !song.measures.isEmpty else { return nil }
        let first = min(max(0, firstMeasure), song.measures.count - 1)
        let last = min(max(first, lastMeasure), song.measures.count - 1)
        return song.measures[first].start...song.measures[last].end
    }
}

public struct MetronomeSettings: Sendable, Equatable, Codable {
    public var isEnabled = false
    public var volume: Float = 0.6
    /// Clicks per beat: 0.25, 0.5, 1, 2 or 4.
    public var clicksPerBeat: Double = 1
    public var accentsFirstBeat = true

    public init(isEnabled: Bool = false, volume: Float = 0.6, clicksPerBeat: Double = 1, accentsFirstBeat: Bool = true) {
        self.isEnabled = isEnabled
        self.volume = volume
        self.clicksPerBeat = clicksPerBeat
        self.accentsFirstBeat = accentsFirstBeat
    }
}

/// Timing tolerances, in real seconds (independent of the playback speed).
public struct JudgingWindows: Sendable, Equatable, Codable {
    public var perfect: TimeInterval = 0.05
    public var good: TimeInterval = 0.3

    public init(perfect: TimeInterval = 0.05, good: TimeInterval = 0.3) {
        self.perfect = perfect
        self.good = max(perfect, good)
    }
}

/// Everything the player can tune for a practice session.
public struct PracticeSettings: Sendable, Equatable, Codable {
    public static let speedRange: ClosedRange<Double> = 0.1...2.0
    public static let speedPresets: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    public static let transposeRange: ClosedRange<Int> = -12...12

    public var hands: Set<Hand> = [.left, .right]
    public var mode: PracticeMode = .learn
    public var speed: Double = 1 {
        didSet { speed = Self.clampedSpeed(speed) }
    }
    public var loop: LoopRange?
    public var metronome = MetronomeSettings()
    public var countdownEnabled = true
    public var transpose = 0 {
        didSet { transpose = min(Self.transposeRange.upperBound, max(Self.transposeRange.lowerBound, transpose)) }
    }
    /// "Don't play my part": notes of the active hands only sound when the player plays them.
    public var muteMyPart = false
    public var handAssignment = HandAssignment()
    public var mutedTracks: Set<Int> = []
    public var windows = JudgingWindows()
    /// Wait mode: real seconds the song keeps going after a note is due before it stops and waits.
    /// A note played within this delay keeps the music flowing.
    public var waitTolerance: TimeInterval = 0.25 {
        didSet { waitTolerance = min(Self.waitToleranceRange.upperBound, max(0, waitTolerance)) }
    }
    public static let waitToleranceRange: ClosedRange<TimeInterval> = 0...1
    /// Play a short cue on wrong keys.
    public var wrongNoteSound = false

    public init() {}

    public init(handAssignment: HandAssignment) {
        self.handAssignment = handAssignment
    }

    public static func clampedSpeed(_ speed: Double) -> Double {
        let value = speed.isFinite ? speed : 1
        return (min(speedRange.upperBound, max(speedRange.lowerBound, value)) * 100).rounded() / 100
    }
}

extension PracticeSettings {
    enum CodingKeys: String, CodingKey {
        case hands, mode, speed, loop, metronome, countdownEnabled, transpose, muteMyPart
        case handAssignment, mutedTracks, windows, wrongNoteSound, waitTolerance
    }

    /// Missing keys keep their default, so settings saved by an older version still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hands = try container.decodeIfPresent(Set<Hand>.self, forKey: .hands) ?? hands
        mode = try container.decodeIfPresent(PracticeMode.self, forKey: .mode) ?? mode
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        loop = try container.decodeIfPresent(LoopRange.self, forKey: .loop)
        metronome = try container.decodeIfPresent(MetronomeSettings.self, forKey: .metronome) ?? metronome
        countdownEnabled = try container.decodeIfPresent(Bool.self, forKey: .countdownEnabled) ?? countdownEnabled
        transpose = try container.decodeIfPresent(Int.self, forKey: .transpose) ?? transpose
        muteMyPart = try container.decodeIfPresent(Bool.self, forKey: .muteMyPart) ?? muteMyPart
        handAssignment = try container.decodeIfPresent(HandAssignment.self, forKey: .handAssignment) ?? handAssignment
        mutedTracks = try container.decodeIfPresent(Set<Int>.self, forKey: .mutedTracks) ?? mutedTracks
        windows = try container.decodeIfPresent(JudgingWindows.self, forKey: .windows) ?? windows
        wrongNoteSound = try container.decodeIfPresent(Bool.self, forKey: .wrongNoteSound) ?? wrongNoteSound
        waitTolerance = try container.decodeIfPresent(TimeInterval.self, forKey: .waitTolerance) ?? waitTolerance
    }
}
