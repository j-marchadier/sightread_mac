import Foundation

/// Turns a ``MIDIFile`` into a ``Song``.
public enum MIDISongBuilder {
    public static func song(from data: Data) throws(MIDIFileError) -> Song {
        try song(from: MIDIFileReader.read(data))
    }

    public static func song(from file: MIDIFile) -> Song {
        let ppq = file.ticksPerQuarter
        var tempoChanges: [(tick: Int, microsecondsPerQuarter: Int)] = []
        var timeSignatureEvents: [(tick: Int, signature: TimeSignature)] = []
        var keyEvents: [(tick: Int, fifths: Int)] = []
        var lastEventTick = 0

        for track in file.tracks {
            for event in track {
                lastEventTick = max(lastEventTick, event.tick)
                switch event.kind {
                case let .tempo(tempo): tempoChanges.append((event.tick, tempo))
                case let .timeSignature(n, d): timeSignatureEvents.append((event.tick, TimeSignature(n, d)))
                case let .keySignature(fifths, _): keyEvents.append((event.tick, fifths))
                default: break
                }
            }
        }
        let tempoMap = TempoMap(ticksPerQuarter: ppq, changes: tempoChanges)

        // Collect notes per output track. Format 0 files hold every part in one track: split by channel.
        let sourceTracks = file.format == 0 ? splitByChannel(file.tracks) : file.tracks.enumerated().map { ($0.offset, $0.element) }
        var tracks: [Track] = []
        var rawNotes: [(pitch: UInt8, velocity: UInt8, track: Int, start: Int, end: Int)] = []
        var sustain: [(tick: Int, track: Int, down: Bool)] = []

        for (sourceIndex, events) in sourceTracks {
            let paired = pairNotes(events)
            guard !paired.notes.isEmpty else { continue }
            let trackIndex = tracks.count
            var name: String?
            var program: UInt8?
            for event in events {
                switch event.kind {
                case let .trackName(text) where name == nil && !text.isEmpty: name = text
                case let .programChange(_, value) where program == nil: program = value
                case let .controlChange(_, 64, value): sustain.append((event.tick, trackIndex, value >= 64))
                default: break
                }
            }
            tracks.append(Track(name: name, program: program, channel: paired.firstChannel, sourceIndex: sourceIndex))
            rawNotes += paired.notes.map { ($0.pitch, $0.velocity, trackIndex, $0.start, $0.end) }
        }

        rawNotes.sort { ($0.start, $0.pitch, $0.track) < ($1.start, $1.pitch, $1.track) }
        let lastNoteEnd = rawNotes.map(\.end).max() ?? 0
        let timeSignatures = normalizedTimeSignatures(timeSignatureEvents)
        let measures = MeasureBuilder.measures(
            timeSignatures: timeSignatures,
            endTick: lastNoteEnd > 0 ? lastNoteEnd : lastEventTick,
            tempoMap: tempoMap
        )

        var song = Song(
            tracks: tracks,
            notes: [],
            measures: measures,
            tempoMap: tempoMap,
            timeSignatures: timeSignatures,
            keySignatures: [],
            sustainChanges: sustain.sorted { $0.tick < $1.tick }.map {
                SustainChange(tick: $0.tick, time: tempoMap.seconds(atTick: $0.tick), track: $0.track, isDown: $0.down)
            }
        )
        song.notes = rawNotes.enumerated().map { index, raw in
            let start = tempoMap.seconds(atTick: raw.start)
            return Note(
                id: index, pitch: raw.pitch, velocity: raw.velocity, track: raw.track,
                startTick: raw.start, durationTicks: raw.end - raw.start,
                start: start, duration: tempoMap.seconds(atTick: raw.end) - start,
                measureIndex: song.measureIndex(atTick: raw.start)
            )
        }
        song.keySignatures = keySignatures(from: keyEvents, notes: song.notes)
        return song
    }

    /// Key from the file, with one twist: many programs write "C major" by default, so C is only
    /// trusted when the piece uses no black key at all. Unknown keys yield an empty list.
    static func keySignatures(from events: [(tick: Int, fifths: Int)], notes: [Note]) -> [KeySignatureChange] {
        var changes: [KeySignatureChange] = []
        var byTick: [Int: Int] = [:]
        for event in events { byTick[event.tick] = event.fifths } // last event at a tick wins
        for tick in byTick.keys.sorted() {
            guard let key = KeySignature(fifths: byTick[tick]!) else { continue }
            if changes.last?.key != key { changes.append(KeySignatureChange(tick: tick, key: key)) }
        }
        if let first = changes.first {
            changes[0].tick = 0
            if first.key == .cMajor && changes.count == 1 { changes.removeAll() }
        }
        if changes.isEmpty && !notes.contains(where: { PianoKeys.isBlack($0.pitch) }) {
            changes = [KeySignatureChange(tick: 0, key: .cMajor)]
        }
        return changes
    }

    static func normalizedTimeSignatures(_ events: [(tick: Int, signature: TimeSignature)]) -> [TimeSignatureChange] {
        var byTick: [Int: TimeSignature] = [:]
        for event in events { byTick[event.tick] = event.signature }
        var changes: [TimeSignatureChange] = []
        for tick in byTick.keys.sorted() where changes.last?.signature != byTick[tick] {
            changes.append(TimeSignatureChange(tick: tick, signature: byTick[tick]!))
        }
        if changes.first.map({ $0.tick > 0 }) ?? true {
            changes.insert(TimeSignatureChange(tick: 0, signature: .common), at: 0)
        }
        return changes
    }

    private struct PairedNotes {
        var notes: [(pitch: UInt8, velocity: UInt8, start: Int, end: Int)] = []
        var firstChannel: UInt8?
    }

    /// Matches note-on and note-off events per channel and pitch, first in first out.
    /// Notes still sounding at the end of the track are closed on the last event.
    private static func pairNotes(_ events: [MIDIEvent]) -> PairedNotes {
        var result = PairedNotes()
        var open: [Int: [(start: Int, velocity: UInt8)]] = [:]
        var lastTick = 0
        for event in events {
            lastTick = max(lastTick, event.tick)
            switch event.kind {
            case let .noteOn(channel, pitch, velocity):
                if result.firstChannel == nil { result.firstChannel = channel }
                open[Int(channel) << 8 | Int(pitch), default: []].append((event.tick, velocity))
            case let .noteOff(channel, pitch, _):
                let key = Int(channel) << 8 | Int(pitch)
                guard var queue = open[key], !queue.isEmpty else { continue }
                let started = queue.removeFirst()
                open[key] = queue
                result.notes.append((pitch, started.velocity, started.start, event.tick))
            default:
                break
            }
        }
        for (key, queue) in open {
            for started in queue {
                result.notes.append((UInt8(key & 0x7F), started.velocity, started.start, max(lastTick, started.start)))
            }
        }
        return result
    }

    private static func splitByChannel(_ tracks: [[MIDIEvent]]) -> [(Int, [MIDIEvent])] {
        var perChannel: [UInt8: [MIDIEvent]] = [:]
        var shared: [MIDIEvent] = []
        for event in tracks.flatMap({ $0 }) {
            switch event.kind {
            case let .noteOn(channel, _, _), let .noteOff(channel, _, _),
                 let .controlChange(channel, _, _), let .programChange(channel, _):
                perChannel[channel, default: []].append(event)
            default:
                shared.append(event)
            }
        }
        // Track names apply to every part; keep them so each part can still be labelled.
        let names = shared.filter { if case .trackName = $0.kind { true } else { false } }
        return perChannel.keys.sorted().map { channel in
            (Int(channel), (names + perChannel[channel]!).sorted { $0.tick < $1.tick })
        }
    }
}

/// Builds measures from time signatures, covering the piece up to `endTick`.
public enum MeasureBuilder {
    public static func measures(timeSignatures: [TimeSignatureChange], endTick: Int, tempoMap: TempoMap) -> [Measure] {
        var measures: [Measure] = []
        let ppq = tempoMap.ticksPerQuarter
        for (index, change) in timeSignatures.enumerated() {
            let segmentEnd = index + 1 < timeSignatures.count ? timeSignatures[index + 1].tick : endTick
            let length = change.signature.ticksPerMeasure(ticksPerQuarter: ppq)
            guard length > 0, segmentEnd > change.tick else { continue }
            let count = (segmentEnd - change.tick + length - 1) / length
            for i in 0..<count {
                let start = change.tick + i * length
                let end = start + length
                measures.append(Measure(
                    number: measures.count + 1, startTick: start, endTick: end,
                    start: tempoMap.seconds(atTick: start), end: tempoMap.seconds(atTick: end)
                ))
            }
        }
        if measures.isEmpty {
            let length = TimeSignature.common.ticksPerMeasure(ticksPerQuarter: ppq)
            measures.append(Measure(number: 1, startTick: 0, endTick: length, start: 0, end: tempoMap.seconds(atTick: length)))
        }
        return measures
    }
}
