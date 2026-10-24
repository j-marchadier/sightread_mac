import Foundation
import MyPianoCore

/// What a player window opens: a library song or a freshly generated exercise.
enum PlayerTarget: Hashable, Codable {
    case song(id: String)
    case noteReading(NoteReadingExercise, seed: UInt64)
    case phrase(PhraseExercise, seed: UInt64)

    var isExercise: Bool {
        if case .song = self { false } else { true }
    }

    /// The same exercise with new notes.
    func regenerated() -> PlayerTarget {
        switch self {
        case .song: self
        case let .noteReading(exercise, _): .noteReading(exercise, seed: UInt64.random(in: 1...UInt64.max))
        case let .phrase(exercise, _): .phrase(exercise, seed: UInt64.random(in: 1...UInt64.max))
        }
    }
}
