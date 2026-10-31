import Foundation

public enum Hand: String, Sendable, Codable, CaseIterable {
    case left, right
}

/// Which notes belong to which hand. Tracks not listed are accompaniment (heard, not practised).
public struct HandAssignment: Sendable, Equatable, Codable {
    public var leftTracks: Set<Int>
    public var rightTracks: Set<Int>
    /// Tracks holding both hands: notes at or above the split pitch go to the right hand.
    public var splitTracks: [Int: UInt8]

    public init(leftTracks: Set<Int> = [], rightTracks: Set<Int> = [], splitTracks: [Int: UInt8] = [:]) {
        self.leftTracks = leftTracks
        self.rightTracks = rightTracks
        self.splitTracks = splitTracks
    }

    public func hand(for note: Note) -> Hand? {
        if let split = splitTracks[note.track] { return note.pitch >= split ? .right : .left }
        if rightTracks.contains(note.track) { return .right }
        if leftTracks.contains(note.track) { return .left }
        return nil
    }

    public func tracks(for hand: Hand) -> Set<Int> {
        let split = Set(splitTracks.keys)
        return (hand == .left ? leftTracks : rightTracks).union(split)
    }
}

/// Guesses which tracks the left and right hands play.
public enum HandAssigner {
    static let leftNames: Set<String> = ["bass", "left", "lh", "l.h.", "left hand", "main gauche", "mg", "m.g."]
    static let rightNames: Set<String> = ["treble", "lead", "rh", "r.h.", "right", "right hand", "student", "main droite", "md", "m.d."]

    public static func assign(_ song: Song) -> HandAssignment {
        let noteCounts = Dictionary(grouping: song.notes, by: \.track).mapValues(\.count)
        let melodic = song.tracks.indices.filter { noteCounts[$0, default: 0] > 0 && !song.tracks[$0].isPercussion }
        guard !melodic.isEmpty else { return HandAssignment() }

        if let byStaff = assignByStaff(song, candidates: melodic) { return byStaff }
        if let byName = assignByName(song, candidates: melodic) { return byName }

        let pianos = melodic.filter { song.tracks[$0].isPiano }
        let pair = Array((pianos.count >= 2 ? pianos : melodic).prefix(2))
        if pair.count == 2 {
            let (a, b) = (pair[0], pair[1])
            return averagePitch(song, a) < averagePitch(song, b)
                ? HandAssignment(leftTracks: [a], rightTracks: [b])
                : HandAssignment(leftTracks: [b], rightTracks: [a])
        }
        return assignSingleTrack(song, pair[0])
    }

    /// Score files: in a part written on several staves, the upper staff is the right hand.
    private static func assignByStaff(_ song: Song, candidates: [Int]) -> HandAssignment? {
        let staffOfTrack = Dictionary(song.notes.compactMap { note in note.staff.map { (note.track, $0) } }, uniquingKeysWith: { a, _ in a })
        guard !staffOfTrack.isEmpty else { return nil }
        let parts = Dictionary(grouping: candidates, by: { song.tracks[$0].sourceIndex })
        let multiStaff = parts.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }
        guard let part = multiStaff.first(where: { $0.value.contains { song.tracks[$0].isPiano } }) ?? multiStaff.first else { return nil }
        let sorted = part.value.sorted { staffOfTrack[$0, default: 1] < staffOfTrack[$1, default: 1] }
        return HandAssignment(leftTracks: Set(sorted.dropFirst()), rightTracks: [sorted[0]])
    }

    private static func assignByName(_ song: Song, candidates: [Int]) -> HandAssignment? {
        func normalized(_ track: Int) -> String {
            (song.tracks[track].name ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        }
        guard let left = candidates.first(where: { leftNames.contains(normalized($0)) }),
              let right = candidates.first(where: { rightNames.contains(normalized($0)) }) else { return nil }
        return HandAssignment(leftTracks: [left], rightTracks: [right])
    }

    /// A lone track is split between the hands only when it really looks like a two-handed part:
    /// a wide range and frequent simultaneous notes an octave or more apart. Otherwise it is a
    /// melody, given to the right hand (or the left hand if it lies low).
    private static func assignSingleTrack(_ song: Song, _ track: Int) -> HandAssignment {
        let notes = song.notes(inTrack: track)
        let pitches = notes.map { Int($0.pitch) }
        let range = (pitches.max() ?? 0) - (pitches.min() ?? 0)

        var wideOnsets = 0
        var onsets = 0
        for group in Dictionary(grouping: notes, by: \.startTick).values {
            onsets += 1
            let sounding = notes.filter { $0.startTick <= group[0].startTick && $0.endTick > group[0].startTick }.map { Int($0.pitch) }
            if (sounding.max() ?? 0) - (sounding.min() ?? 0) >= 12 { wideOnsets += 1 }
        }
        if range >= 24 && onsets > 0 && Double(wideOnsets) / Double(onsets) >= 0.1 {
            return HandAssignment(splitTracks: [track: PianoKeys.middleC])
        }
        return averagePitch(song, track) < 55 ? HandAssignment(leftTracks: [track]) : HandAssignment(rightTracks: [track])
    }

    private static func averagePitch(_ song: Song, _ track: Int) -> Double {
        let pitches = song.notes(inTrack: track).map { Double($0.pitch) }
        return pitches.isEmpty ? 0 : pitches.reduce(0, +) / Double(pitches.count)
    }
}
