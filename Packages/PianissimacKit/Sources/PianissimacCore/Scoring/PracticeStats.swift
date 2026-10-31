import Foundation

public enum Grade: String, Sendable, Codable {
    case perfect
    case good
}

/// Counters of a practice session.
public struct PracticeStats: Sendable, Equatable, Codable {
    public var perfect = 0
    public var good = 0
    public var missed = 0
    /// Keys pressed that matched no expected note.
    public var wrong = 0
    public var streak = 0
    public var bestStreak = 0
    /// Real time spent holding correctly played notes, summed over notes.
    public var heldSeconds: TimeInterval = 0

    public init() {}

    public var hits: Int { perfect + good }

    /// Share of correct actions, from 0 to 1. A session without any action counts as perfect.
    public var accuracy: Double {
        let total = hits + missed + wrong
        return total == 0 ? 1 : Double(hits) / Double(total)
    }

    /// Accuracy as a rounded percentage.
    public var accuracyPercent: Int { Int((accuracy * 100).rounded()) }

    /// Combined score: 100 per perfect, 50 per good, −25 per wrong key,
    /// plus one point per tenth of a second of correctly held notes.
    public var score: Int {
        perfect * 100 + good * 50 - wrong * 25 + Int(heldSeconds * 10)
    }

    mutating func recordHit(_ grade: Grade) {
        switch grade {
        case .perfect: perfect += 1
        case .good: good += 1
        }
        streak += 1
        bestStreak = max(bestStreak, streak)
    }

    mutating func recordMiss() {
        missed += 1
        streak = 0
    }

    mutating func recordWrongKey() {
        wrong += 1
        streak = 0
    }
}
