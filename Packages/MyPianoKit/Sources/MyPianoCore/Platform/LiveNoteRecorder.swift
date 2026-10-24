import Foundation

/// A note played live, for the free-play display (times are host seconds).
public struct LiveNote: Sendable, Equatable {
    public var pitch: UInt8
    public var start: TimeInterval
    /// `nil` while the key is held.
    public var end: TimeInterval?
}

/// Remembers recently played notes so free play can draw them rising from the keyboard.
/// Thread-safe: the MIDI thread records, the renderer reads.
public final class LiveNoteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notes: [LiveNote] = []
    private let memory: TimeInterval

    /// - Parameter memory: How long released notes are kept, in seconds.
    public init(memory: TimeInterval = 12) {
        self.memory = memory
    }

    public func apply(_ event: InputEvent) {
        lock.lock()
        defer { lock.unlock() }
        switch event.kind {
        case let .noteOn(pitch, _):
            notes.append(LiveNote(pitch: pitch, start: event.time, end: nil))
        case let .noteOff(pitch):
            if let index = notes.lastIndex(where: { $0.pitch == pitch && $0.end == nil }) {
                notes[index].end = max(event.time, notes[index].start)
            }
        case .sustain:
            break
        }
        notes.removeAll { ($0.end ?? .infinity) < event.time - memory }
    }

    /// Notes still worth drawing at `now`.
    public func notes(at now: TimeInterval) -> [LiveNote] {
        lock.lock()
        defer { lock.unlock() }
        return notes.filter { ($0.end ?? now) >= now - memory }
    }

    public func clear() {
        lock.lock()
        notes.removeAll()
        lock.unlock()
    }
}
