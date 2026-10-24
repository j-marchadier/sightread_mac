import Foundation

/// A finger for a note: 1 = thumb … 5 = little finger.
public struct Finger: Sendable, Equatable, Hashable {
    public var number: UInt8
    /// Written in the score, as opposed to suggested by MyPiano.
    public var isWritten: Bool

    public init(_ number: UInt8, isWritten: Bool) {
        self.number = number
        self.isWritten = isWritten
    }
}

/// Suggests fingers for each hand by finding the least awkward sequence over the whole piece.
///
/// Each hand's notes are grouped by onset (single notes and chords). Every way of fingering a
/// group has a cost (stretch inside a chord, thumb or little finger on a black key, weak fourth
/// finger) and every move between two groups too (how far each pair of fingers comfortably
/// reaches, crossings, repeating a finger on another key). Dynamic programming picks the
/// cheapest path. The distances follow the comfortable and practical spans of each finger pair
/// published in piano pedagogy research (Parncutt et al., 1997). Written fingers are kept and
/// the suggestions are built around them. The left hand is handled as a mirrored right hand.
public enum FingeringSuggester {
    /// Fingers for each note of the song (indexed by note id); `nil` for accompaniment notes.
    public static func fingers(for song: Song, hands: [Hand?], transpose: Int = 0) -> [Finger?] {
        var result = [Finger?](repeating: nil, count: song.notes.count)
        for hand in Hand.allCases {
            let notes = song.notes.filter { hands.indices.contains($0.id) && hands[$0.id] == hand }
            for (id, finger) in suggest(notes, hand: hand, transpose: transpose) { result[id] = finger }
        }
        return result
    }

    // MARK: Model

    private struct Slice {
        var ids: [Int]          // ordered from the thumb side to the little-finger side
        var pitches: [Int]      // real pitches, same order
        var mirrored: [Int]     // pitches as seen by a right hand (negated for the left hand)
        var written: [UInt8?]
        var start: TimeInterval
    }

    /// Comfortable and practical spans in semitones for each pair of fingers (lower finger first),
    /// as (minPractical, minComfortable, minRelaxed, maxRelaxed, maxComfortable, maxPractical).
    private static let spans: [[Int]: (Int, Int, Int, Int, Int, Int)] = [
        [1, 2]: (-5, -3, 1, 5, 8, 10), [1, 3]: (-4, -2, 3, 7, 10, 12), [1, 4]: (-3, -1, 5, 9, 12, 14),
        [1, 5]: (-1, 1, 7, 10, 13, 15), [2, 3]: (1, 1, 1, 2, 3, 5), [2, 4]: (1, 1, 3, 4, 5, 7),
        [2, 5]: (2, 2, 5, 6, 8, 10), [3, 4]: (1, 1, 1, 2, 2, 4), [3, 5]: (1, 1, 3, 4, 5, 7),
        [4, 5]: (1, 1, 1, 2, 3, 5),
    ]

    private static func suggest(_ notes: [Note], hand: Hand, transpose: Int) -> [(Int, Finger)] {
        guard !notes.isEmpty else { return [] }
        let sign = hand == .right ? 1 : -1
        var slices: [Slice] = []
        for group in Dictionary(grouping: notes, by: \.startTick).sorted(by: { $0.key < $1.key }) {
            let ordered = group.value
                .map { (note: $0, pitch: Int(PianoKeys.transpose($0.pitch, by: transpose))) }
                .sorted { $0.pitch * sign < $1.pitch * sign }
                .prefix(5)
            slices.append(Slice(
                ids: ordered.map(\.note.id), pitches: ordered.map(\.pitch), mirrored: ordered.map { $0.pitch * sign },
                written: ordered.map(\.note.finger), start: group.value[0].start
            ))
        }

        // Candidates: increasing fingers from the thumb side, matching written fingers.
        let candidates = slices.map { slice -> [[UInt8]] in
            let all = combinations(of: slice.ids.count).filter { fingers in
                zip(fingers, slice.written).allSatisfy { $1 == nil || $0 == $1 }
            }
            return all.isEmpty ? [slice.written.map { $0 ?? 1 }] : all
        }

        // Dynamic programming over the slices.
        var cost = candidates[0].map { intrinsic($0, slices[0]) }
        var back: [[Int]] = [Array(repeating: -1, count: candidates[0].count)]
        for s in 1..<slices.count {
            let gap = slices[s].start - slices[s - 1].start
            let weight = gap > 1 ? 0.3 : 1 // after a rest the hand moves freely
            var row: [Double] = []
            var from: [Int] = []
            for candidate in candidates[s] {
                var best = Double.infinity
                var bestIndex = 0
                for (p, previous) in candidates[s - 1].enumerated() {
                    let total = cost[p] + transition(previous, slices[s - 1], candidate, slices[s]) * weight
                    if total < best { best = total; bestIndex = p }
                }
                row.append(best + intrinsic(candidate, slices[s]))
                from.append(bestIndex)
            }
            cost = row
            back.append(from)
        }

        var index = cost.indices.min { cost[$0] < cost[$1] } ?? 0
        var result: [(Int, Finger)] = []
        for s in stride(from: slices.count - 1, through: 0, by: -1) {
            let fingers = candidates[s][index]
            for (i, id) in slices[s].ids.enumerated() {
                result.append((id, Finger(fingers[i], isWritten: slices[s].written[i] == fingers[i])))
            }
            index = back[s][index]
        }
        return result
    }

    private static func combinations(of count: Int) -> [[UInt8]] {
        var result: [[UInt8]] = []
        func build(_ current: [UInt8], next: UInt8) {
            if current.count == count { result.append(current); return }
            guard next <= 5 else { return }
            for finger in next...5 where 5 - Int(finger) >= count - current.count - 1 {
                build(current + [finger], next: finger + 1)
            }
        }
        build([], next: 1)
        return result
    }

    // MARK: Costs

    private static func intrinsic(_ fingers: [UInt8], _ slice: Slice) -> Double {
        var cost = 0.0
        for (finger, pitch) in zip(fingers, slice.pitches) {
            let black = PianoKeys.isBlack(UInt8(clamping: pitch))
            if finger == 4 { cost += 0.5 }
            if black && finger == 1 { cost += 1.5 }
            if black && finger == 5 { cost += 1 }
        }
        // Stretch inside a chord.
        for i in fingers.indices {
            for j in fingers.indices where j > i {
                cost += span(fingers[i], slice.mirrored[i], fingers[j], slice.mirrored[j], inChord: true)
            }
        }
        return cost
    }

    private static func transition(_ a: [UInt8], _ sliceA: Slice, _ b: [UInt8], _ sliceB: Slice) -> Double {
        if a.count == 1 && b.count == 1 {
            return move(a[0], sliceA.mirrored[0], b[0], sliceB.mirrored[0])
        }
        // Chords: follow the outer fingers.
        let low = move(a[0], sliceA.mirrored[0], b[0], sliceB.mirrored[0])
        let high = move(a[a.count - 1], sliceA.mirrored[a.count - 1], b[b.count - 1], sliceB.mirrored[b.count - 1])
        return (low + high) / 2
    }

    /// Going from one key and finger to the next.
    private static func move(_ f1: UInt8, _ p1: Int, _ f2: UInt8, _ p2: Int) -> Double {
        if f1 == f2 { return p1 == p2 ? 0 : 8 + Double(abs(p2 - p1)) * 0.5 }
        return span(f1, p1, f2, p2, inChord: false)
    }

    /// How awkward it is to hold or reach two keys with two different fingers.
    private static func span(_ f1: UInt8, _ p1: Int, _ f2: UInt8, _ p2: Int, inChord: Bool) -> Double {
        var (low, high, distance) = (f1, f2, p2 - p1)
        if low > high { (low, high, distance) = (f2, f1, -distance) }
        guard let (minPractical, minComfortable, minRelaxed, maxRelaxed, maxComfortable, maxPractical) = spans[[Int(low), Int(high)]] else { return 0 }
        let thumb = low == 1
        var cost = 0.0
        if distance < minComfortable { cost += 2 * Double(minComfortable - distance) }
        if distance > maxComfortable { cost += 2 * Double(distance - maxComfortable) }
        if distance < minRelaxed { cost += (thumb ? 1 : 2) * Double(minRelaxed - max(distance, minComfortable)) }
        if distance > maxRelaxed { cost += (thumb ? 1 : 2) * Double(min(distance, maxComfortable) - maxRelaxed) }
        if distance < minPractical { cost += 10 * Double(minPractical - distance) }
        if distance > maxPractical { cost += 10 * Double(distance - maxPractical) }
        // Crossings: possible with the thumb (passing under or over it) but a hand movement,
        // impossible in a chord.
        if distance < 0 { cost += inChord ? 20 : 2 }
        return cost
    }
}
