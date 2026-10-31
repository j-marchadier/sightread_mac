import Foundation

/// Horizontal geometry of a piano keyboard: where each key (and its falling-note lane) lies.
///
/// Units are points. White keys share the width evenly; black keys sit across the boundary
/// between their white neighbours, slightly shifted as on a real piano.
public struct KeyboardLayout: Sendable, Equatable {
    public struct Key: Sendable, Equatable {
        public let pitch: UInt8
        public let isBlack: Bool
        public let x: Double
        public let width: Double

        public var midX: Double { x + width / 2 }
        public var maxX: Double { x + width }
    }

    public let range: ClosedRange<UInt8>
    public let width: Double
    public let whiteKeyWidth: Double
    public let blackKeyWidth: Double
    /// Keys by pitch, from `range.lowerBound`.
    public let keys: [Key]

    /// Height of white keys for a given maximum, keeping a piano-like aspect ratio.
    public func whiteKeyHeight(maximum: Double) -> Double {
        min(maximum, whiteKeyWidth * 5.6)
    }

    public static let blackKeyHeightRatio = 0.63

    /// Shift of each black key from the boundary of its white neighbours, in white-key widths.
    private static let blackKeyOffsets: [Int: Double] = [1: -0.08, 3: 0.08, 6: -0.1, 8: 0, 10: 0.1]

    /// - Parameter range: Bounds are moved outward to white keys when needed.
    public init(range: ClosedRange<UInt8>, width: Double) {
        var lower = range.lowerBound
        var upper = range.upperBound
        if PianoKeys.isBlack(lower) && lower > 0 { lower -= 1 }
        if PianoKeys.isBlack(upper) && upper < 127 { upper += 1 }
        self.range = lower...upper
        self.width = max(1, width)

        let whiteCount = (lower...upper).filter { !PianoKeys.isBlack($0) }.count
        whiteKeyWidth = self.width / Double(max(1, whiteCount))
        blackKeyWidth = whiteKeyWidth * 0.58

        var keys: [Key] = []
        var whiteIndex = 0
        for pitch in lower...upper {
            if PianoKeys.isBlack(pitch) {
                let boundary = Double(whiteIndex) * whiteKeyWidth
                let offset = Self.blackKeyOffsets[Int(pitch) % 12, default: 0] * whiteKeyWidth
                keys.append(Key(pitch: pitch, isBlack: true, x: boundary + offset - blackKeyWidth / 2, width: blackKeyWidth))
            } else {
                keys.append(Key(pitch: pitch, isBlack: false, x: Double(whiteIndex) * whiteKeyWidth, width: whiteKeyWidth))
                whiteIndex += 1
            }
        }
        self.keys = keys
    }

    public func key(for pitch: UInt8) -> Key? {
        guard range.contains(pitch) else { return nil }
        return keys[Int(pitch - range.lowerBound)]
    }

    /// The key under a point of the keyboard (`y` from the top of the keys). Black keys win in their upper part.
    public func key(atX x: Double, y: Double, whiteKeyHeight: Double) -> UInt8? {
        guard x >= 0, x < width, y >= 0, y <= whiteKeyHeight else { return nil }
        if y <= whiteKeyHeight * Self.blackKeyHeightRatio,
           let black = keys.first(where: { $0.isBlack && x >= $0.x && x < $0.maxX }) {
            return black.pitch
        }
        return keys.first { !$0.isBlack && x >= $0.x && x < $0.maxX }?.pitch
    }

    /// Keys to show for a song: the full 88-key piano, or the song's range with some margin
    /// (at least two octaves, centred on the music).
    public static func displayRange(for song: Song, transpose: Int, fullKeyboard: Bool) -> ClosedRange<UInt8> {
        let full = PianoKeys.lowest...PianoKeys.highest
        guard !fullKeyboard, !song.notes.isEmpty else { return full }
        let pitches = song.notes.map { Int(PianoKeys.transpose($0.pitch, by: transpose)) }
        var lower = (pitches.min() ?? 60) - 2
        var upper = (pitches.max() ?? 72) + 2
        let minimumSpan = 24
        if upper - lower < minimumSpan {
            let missing = minimumSpan - (upper - lower)
            lower -= missing / 2
            upper += missing - missing / 2
        }
        lower = max(Int(PianoKeys.lowest), lower)
        upper = min(Int(PianoKeys.highest), max(upper, lower + minimumSpan))
        return UInt8(lower)...UInt8(upper)
    }
}
