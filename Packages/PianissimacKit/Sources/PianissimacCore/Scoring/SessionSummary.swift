import Foundation

/// What a practice session achieved, for the end-of-session sheet and the progress history.
public struct SessionSummary: Sendable, Equatable, Codable {
    public var startedAt: Date
    /// Real time spent playing (pauses excluded).
    public var practiceSeconds: TimeInterval
    public var mode: PracticeMode
    public var speed: Double
    public var hands: Set<Hand>
    public var loop: LoopRange?
    public var stats: PracticeStats
    /// Share of the song (or loop) reached, from 0 to 1.
    public var completion: Double

    public init(startedAt: Date, practiceSeconds: TimeInterval, settings: PracticeSettings, stats: PracticeStats, completion: Double) {
        self.startedAt = startedAt
        self.practiceSeconds = practiceSeconds
        mode = settings.mode
        speed = settings.speed
        hands = settings.hands
        loop = settings.loop
        self.stats = stats
        self.completion = min(1, max(0, completion))
    }

    /// Sessions too short or without any judged note are not worth recording.
    public var isWorthRecording: Bool {
        practiceSeconds >= 10 && (mode == .listen || stats.hits + stats.missed + stats.wrong > 0)
    }
}
