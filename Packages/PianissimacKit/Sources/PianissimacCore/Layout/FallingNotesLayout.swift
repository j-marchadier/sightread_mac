import Foundation

/// Vertical geometry of the falling-notes view: notes fall towards a hit line at the top of the
/// keyboard and reach it when they start. Units are points; times are song seconds.
public struct FallingNotesLayout: Sendable {
    public struct NoteRect: Sendable, Equatable {
        public let noteID: Int
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    public let keyboard: KeyboardLayout
    /// Y of the hit line (top of the keyboard area).
    public let hitLineY: Double
    public let pointsPerSecond: Double
    public let transpose: Int
    /// Notes shorter than this are drawn this tall so they stay visible.
    public var minimumNoteHeight: Double = 6

    public init(keyboard: KeyboardLayout, hitLineY: Double, pointsPerSecond: Double, transpose: Int = 0) {
        self.keyboard = keyboard
        self.hitLineY = hitLineY
        self.pointsPerSecond = max(1, pointsPerSecond)
        self.transpose = transpose
    }

    /// Y on screen of a song time, given the current time.
    public func y(for songTime: TimeInterval, now: TimeInterval) -> Double {
        hitLineY - (songTime - now) * pointsPerSecond
    }

    /// Song time shown at the top of the view.
    public func visibleUntil(now: TimeInterval) -> TimeInterval {
        now + hitLineY / pointsPerSecond
    }

    public func rect(for note: Note, now: TimeInterval) -> NoteRect? {
        guard let key = keyboard.key(for: PianoKeys.transpose(note.pitch, by: transpose)) else { return nil }
        let bottom = y(for: note.start, now: now)
        let height = max(minimumNoteHeight, note.duration * pointsPerSecond)
        let inset = key.isBlack ? 0.5 : max(1, key.width * 0.08)
        return NoteRect(noteID: note.id, x: key.x + inset, y: bottom - height, width: max(1, key.width - 2 * inset), height: height)
    }

    /// Indices of notes that may be visible between the bottom of the view and its top.
    /// `maxNoteDuration` lets the search start early enough to catch long notes still sounding.
    public func visibleNoteIndices(in song: Song, now: TimeInterval, maxNoteDuration: TimeInterval) -> Range<Int> {
        let earliestStart = now - maxNoteDuration - minimumNoteHeight / pointsPerSecond
        let latestStart = visibleUntil(now: now)
        let lower = firstIndex(in: song.notes) { $0.start >= earliestStart }
        let upper = firstIndex(in: song.notes) { $0.start > latestStart }
        return lower..<max(lower, upper)
    }

    /// Indices of measures whose start line is visible.
    public func visibleMeasureIndices(in song: Song, now: TimeInterval) -> Range<Int> {
        let lower = firstIndex(in: song.measures) { $0.start >= now }
        let upper = firstIndex(in: song.measures) { $0.start > visibleUntil(now: now) }
        return lower..<max(lower, upper)
    }

    private func firstIndex<T>(in array: [T], where predicate: (T) -> Bool) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(array[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

extension Song {
    /// Longest note duration, used to bound visibility searches.
    public var longestNoteDuration: TimeInterval {
        notes.reduce(0) { max($0, $1.duration) }
    }
}
