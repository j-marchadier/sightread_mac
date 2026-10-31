import Foundation

public enum MusicXMLError: Error, Equatable, Sendable {
    /// The data is not well-formed XML.
    case malformedXML(String)
    /// Well-formed XML whose root is not a MusicXML score.
    case notMusicXML
    /// A compressed `.mxl` file without a readable score inside.
    case invalidCompressedArchive
    /// The score contains no playable note.
    case noNotes
}

/// Imports MusicXML scores (`.musicxml`, `.xml` and compressed `.mxl`).
///
/// - Each staff of each part becomes a track; notes keep their staff so hands can follow it.
/// - Repeats (with voltas) are unrolled; tied notes become one playable note.
/// - Written durations, beams, tuplets, rests and spellings are kept in ``NotationHints``.
public enum MusicXMLImporter {
    public static func song(from data: Data) throws(MusicXMLError) -> Song {
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return try song(fromCompressed: data)
        }
        let root: XMLElementNode
        do {
            root = try XMLTree.parse(data)
        } catch {
            throw .malformedXML(String(describing: error))
        }
        return try song(from: root)
    }

    /// Reads a compressed MusicXML archive: the score is named by `META-INF/container.xml`.
    public static func song(fromCompressed data: Data) throws(MusicXMLError) -> Song {
        do {
            let archive = try ZipArchive(data: data)
            var scorePath: String?
            if let container = try? XMLTree.parse(archive.contents(of: "META-INF/container.xml")) {
                scorePath = container.child("rootfiles")?.children("rootfile").first?.attributes["full-path"]
            }
            if scorePath == nil {
                scorePath = archive.entries.map(\.path).first {
                    !$0.hasPrefix("META-INF/") && ($0.hasSuffix(".xml") || $0.hasSuffix(".musicxml"))
                }
            }
            guard let scorePath else { throw MusicXMLError.invalidCompressedArchive }
            return try song(from: archive.contents(of: scorePath))
        } catch let error as MusicXMLError {
            throw error
        } catch {
            throw .invalidCompressedArchive
        }
    }

    static func song(from root: XMLElementNode) throws(MusicXMLError) -> Song {
        let score: XMLElementNode
        switch root.name {
        case "score-partwise": score = root
        case "score-timewise": score = partwise(fromTimewise: root)
        default: throw .notMusicXML
        }
        let builder = ScoreBuilder(score: score)
        var song = builder.build()
        guard !song.notes.isEmpty else { throw .noNotes }
        let title = score.child("work")?.text(of: "work-title") ?? score.text(of: "movement-title")
        song.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        song.composer = score.child("identification")?.children("creator")
            .first { $0.attributes["type"] == "composer" }?.trimmedText.nilIfEmpty
        return song
    }

    /// Rewrites a timewise score (measures containing parts) as a partwise one.
    private static func partwise(fromTimewise root: XMLElementNode) -> XMLElementNode {
        let result = XMLElementNode(name: "score-partwise", attributes: root.attributes)
        for child in root.children where child.name != "measure" {
            result.append(child)
        }
        var parts: [String: XMLElementNode] = [:]
        var order: [String] = []
        for measure in root.children("measure") {
            for part in measure.children("part") {
                let id = part.attributes["id"] ?? ""
                if parts[id] == nil {
                    parts[id] = XMLElementNode(name: "part", attributes: ["id": id])
                    order.append(id)
                }
                let newMeasure = XMLElementNode(name: "measure", attributes: measure.attributes)
                for content in part.children { newMeasure.append(content) }
                parts[id]!.append(newMeasure)
            }
        }
        for id in order { result.append(parts[id]!) }
        return result
    }
}

// MARK: - Score building

private struct ParsedNote {
    var uid: Int
    var part: Int
    var staff: Int
    var voice: Int
    var pitch: Int
    var spelling: SpelledPitch
    var startTick: Int // relative to its measure while parsing, absolute after unrolling
    var durationTicks: Int
    var velocity: UInt8
    var tieStart: Bool
    var tieStop: Bool
    var finger: UInt8?

    var endTick: Int { startTick + durationTicks }
}

private struct ParsedMeasure {
    var notes: [ParsedNote] = []
    var events: [NotatedEvent] = [] // startTick relative to the measure; pitches keep note uids in noteID
    var tempos: [(tick: Int, bpm: Double)] = []
    var timeSignature: TimeSignature?
    var keySignature: KeySignature?
    var length = 0
}

private struct MeasureStructure {
    var number: Int
    var forwardRepeat = false
    var backwardRepeatTimes: Int?
    var endingNumbers: Set<Int> = []
}

private final class ScoreBuilder {
    private let score: XMLElementNode
    private let parts: [XMLElementNode]
    private let partNames: [String: String]
    private let ticksPerQuarter: Int
    private var nextUID = 0

    init(score: XMLElementNode) {
        self.score = score
        parts = score.children("part")
        var names: [String: String] = [:]
        for scorePart in score.child("part-list")?.children("score-part") ?? [] {
            names[scorePart.attributes["id"] ?? ""] = scorePart.text(of: "part-name")
        }
        partNames = names
        ticksPerQuarter = Self.commonTicksPerQuarter(parts)
    }

    /// A resolution that represents every `<divisions>` value exactly (bounded, otherwise 480 with rounding).
    private static func commonTicksPerQuarter(_ parts: [XMLElementNode]) -> Int {
        var result = 480
        for part in parts {
            for measure in part.children("measure") {
                for attributes in measure.children("attributes") {
                    guard let divisions = attributes.int(of: "divisions"), divisions > 0 else { continue }
                    let candidate = lcm(result, divisions)
                    if candidate <= 1_000_000 { result = candidate }
                }
            }
        }
        return result
    }

    func build() -> Song {
        let measureCount = parts.map { $0.children("measure").count }.max() ?? 0
        let structure = readStructure(measureCount: measureCount)
        let parsed: [[ParsedMeasure]] = parts.enumerated().map { index, part in parseMeasures(of: part, partIndex: index) }
        let order = playbackOrder(structure)

        // Unroll measures in playback order.
        var notes: [ParsedNote] = []
        var events: [NotatedEvent] = []
        var tempoChanges: [(tick: Int, microsecondsPerQuarter: Int)] = []
        var timeChanges: [(tick: Int, signature: TimeSignature)] = []
        var keyChanges: [(tick: Int, fifths: Int)] = []
        var measureBounds: [(number: Int, start: Int, end: Int)] = []
        var offset = 0
        var lastTime = TimeSignature.common

        for measureIndex in order {
            let contents = parsed.map { $0.indices.contains(measureIndex) ? $0[measureIndex] : ParsedMeasure() }
            if let signature = contents.first?.timeSignature ?? contents.compactMap(\.timeSignature).first {
                lastTime = signature
                timeChanges.append((offset, signature))
            }
            if let key = contents.first?.keySignature ?? contents.compactMap(\.keySignature).first {
                keyChanges.append((offset, key.fifths))
            }
            var length = contents.map(\.length).max() ?? 0
            if length == 0 { length = lastTime.ticksPerMeasure(ticksPerQuarter: ticksPerQuarter) }
            let unrolledIndex = measureBounds.count
            for content in contents {
                // Each occurrence of a repeated measure gets fresh uids; notated pitches follow them.
                var uidMap: [Int: Int] = [:]
                for var note in content.notes {
                    uidMap[note.uid] = nextUID
                    note.uid = nextUID
                    nextUID += 1
                    note.startTick += offset
                    notes.append(note)
                }
                for var event in content.events {
                    event.startTick += offset
                    event.measureIndex = unrolledIndex
                    for p in event.pitches.indices {
                        event.pitches[p].noteID = event.pitches[p].noteID.flatMap { uidMap[$0] }
                    }
                    events.append(event)
                }
                for tempo in content.tempos {
                    tempoChanges.append((offset + tempo.tick, Int((60_000_000 / tempo.bpm).rounded())))
                }
            }
            measureBounds.append((structure[measureIndex].number, offset, offset + length))
            offset += length
        }

        // Merge tie chains into single playable notes.
        let (merged, chainOwner) = mergeTies(notes)

        let tempoMap = TempoMap(ticksPerQuarter: ticksPerQuarter, changes: tempoChanges)
        let measures = measureBounds.map {
            Measure(number: $0.number, startTick: $0.start, endTick: $0.end,
                    start: tempoMap.seconds(atTick: $0.start), end: tempoMap.seconds(atTick: $0.end))
        }

        // One track per (part, staff), in score order.
        let trackKeys = Array(Set(merged.map { TrackKey(part: $0.part, staff: $0.staff) })).sorted()
        let trackIndex = Dictionary(uniqueKeysWithValues: trackKeys.enumerated().map { ($1, $0) })
        let stavesPerPart = Dictionary(grouping: trackKeys, by: \.part).mapValues(\.count)
        let tracks = trackKeys.map { key -> Track in
            let partName = partNames[parts[key.part].attributes["id"] ?? ""] ?? "Part \(key.part + 1)"
            let name = (stavesPerPart[key.part] ?? 1) > 1 ? "\(partName) (\(key.staff))" : partName
            return Track(name: name, program: nil, channel: nil, sourceIndex: key.part)
        }

        let sorted = merged.sorted { ($0.startTick, $0.pitch, $0.part, $0.staff) < ($1.startTick, $1.pitch, $1.part, $1.staff) }
        var idByUID: [Int: Int] = [:]
        var song = Song(
            tracks: tracks, notes: [], measures: measures, tempoMap: tempoMap,
            timeSignatures: MIDISongBuilder.normalizedTimeSignatures(timeChanges),
            keySignatures: [],
            notation: nil
        )
        song.notes = sorted.enumerated().map { index, note in
            idByUID[note.uid] = index
            let start = tempoMap.seconds(atTick: note.startTick)
            return Note(
                id: index, pitch: UInt8(clamping: note.pitch), velocity: note.velocity,
                track: trackIndex[TrackKey(part: note.part, staff: note.staff)]!,
                startTick: note.startTick, durationTicks: note.durationTicks,
                start: start, duration: tempoMap.seconds(atTick: note.endTick) - start,
                measureIndex: song.measureIndex(atTick: note.startTick), staff: note.staff, finger: note.finger
            )
        }
        song.keySignatures = keySignatureChanges(keyChanges)

        for e in events.indices {
            events[e].track = trackIndex[TrackKey(part: events[e].track, staff: events[e].staff)] ?? 0
            for p in events[e].pitches.indices {
                if let uid = events[e].pitches[p].noteID, let owner = chainOwner[uid] {
                    events[e].pitches[p].noteID = idByUID[owner]
                } else {
                    events[e].pitches[p].noteID = nil
                }
            }
        }
        song.notation = NotationHints(events: events.sorted { ($0.startTick, $0.staff, $0.voice) < ($1.startTick, $1.staff, $1.voice) })
        return song
    }

    // MARK: Structure and repeats

    private func readStructure(measureCount: Int) -> [MeasureStructure] {
        let reference = parts.first?.children("measure") ?? []
        var result: [MeasureStructure] = []
        var activeEnding: Set<Int> = []
        for index in 0..<measureCount {
            let measure = reference.indices.contains(index) ? reference[index] : nil
            var info = MeasureStructure(number: measure.flatMap { leadingInt($0.attributes["number"]) } ?? index + 1)
            var endingStopsHere = false
            for barline in measure?.children("barline") ?? [] {
                if let repeatNode = barline.child("repeat") {
                    if repeatNode.attributes["direction"] == "forward" { info.forwardRepeat = true }
                    if repeatNode.attributes["direction"] == "backward" {
                        info.backwardRepeatTimes = Int(repeatNode.attributes["times"] ?? "") ?? 2
                    }
                }
                if let ending = barline.child("ending") {
                    switch ending.attributes["type"] {
                    case "start": activeEnding = parseEndingNumbers(ending.attributes["number"] ?? "")
                    case "stop", "discontinue": endingStopsHere = true
                    default: break
                    }
                }
            }
            info.endingNumbers = activeEnding
            if endingStopsHere { activeEnding = [] }
            result.append(info)
        }
        return result
    }

    /// Measure indices in the order they are played.
    private func playbackOrder(_ structure: [MeasureStructure]) -> [Int] {
        var order: [Int] = []
        var index = 0
        var repeatStart = 0
        var pass = 1
        var timesPlayed: [Int: Int] = [:]
        var jumpedBack = false
        let maximum = max(1, structure.count) * 16

        while index < structure.count && order.count < maximum {
            let measure = structure[index]
            if measure.forwardRepeat && !jumpedBack {
                repeatStart = index
                pass = 1
            }
            jumpedBack = false
            if measure.endingNumbers.isEmpty {
                if index > 0 && !structure[index - 1].endingNumbers.isEmpty { pass = 1 } // left the volta group
            } else if !measure.endingNumbers.contains(pass) {
                index += 1
                continue
            } else if pass > 1 && measure.backwardRepeatTimes == nil {
                repeatStart = index + 1 // a later backward repeat starts after the final ending
            }
            order.append(index)
            if let times = measure.backwardRepeatTimes {
                let played = timesPlayed[index, default: 1]
                if played < times {
                    timesPlayed[index] = played + 1
                    pass = played + 1
                    index = repeatStart
                    jumpedBack = true
                    continue
                }
                timesPlayed[index] = nil
                if measure.endingNumbers.isEmpty { pass = 1 }
                repeatStart = index + 1
            }
            index += 1
        }
        return order
    }

    // MARK: Measure contents

    private func parseMeasures(of part: XMLElementNode, partIndex: Int) -> [ParsedMeasure] {
        var divisions = 1
        var result: [ParsedMeasure] = []
        for measureNode in part.children("measure") {
            var measure = ParsedMeasure()
            var position = 0
            var lastNoteStart = 0
            var maxPosition = 0

            func ticks(_ duration: Double) -> Int {
                Int((duration * Double(ticksPerQuarter) / Double(divisions)).rounded())
            }

            for element in measureNode.children {
                switch element.name {
                case "attributes":
                    if let value = element.int(of: "divisions"), value > 0 { divisions = value }
                    if let key = element.child("key"), let fifths = key.int(of: "fifths"), let signature = KeySignature(fifths: fifths) {
                        measure.keySignature = signature
                    }
                    if let time = element.child("time"), let beats = time.text(of: "beats"), let beatType = time.int(of: "beat-type") {
                        let numerator = beats.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
                        if numerator > 0 { measure.timeSignature = TimeSignature(numerator, beatType) }
                    }
                case "backup":
                    position = max(0, position - ticks(element.double(of: "duration") ?? 0))
                case "forward":
                    position += ticks(element.double(of: "duration") ?? 0)
                case "direction":
                    if let tempo = element.child("sound")?.attributes["tempo"].flatMap(Double.init), tempo > 0 {
                        measure.tempos.append((position, tempo))
                    }
                case "sound":
                    if let tempo = element.attributes["tempo"].flatMap(Double.init), tempo > 0 {
                        measure.tempos.append((position, tempo))
                    }
                case "note":
                    if element.child("grace") != nil || element.child("cue") != nil { continue }
                    let isChord = element.child("chord") != nil
                    let duration = ticks(element.double(of: "duration") ?? 0)
                    let start = isChord ? lastNoteStart : position
                    let staff = element.int(of: "staff") ?? 1
                    let voice = element.int(of: "voice") ?? 1
                    let event = notatedEvent(for: element, start: start, duration: duration, staff: staff, voice: voice, part: partIndex)

                    if let pitchNode = element.child("pitch"), let step = pitchNode.text(of: "step").flatMap(Step.init(letter:)),
                       let octave = pitchNode.int(of: "octave") {
                        let alter = Int((pitchNode.double(of: "alter") ?? 0).rounded())
                        let spelling = SpelledPitch(step: step, alter: alter, octave: octave)
                        let ties = element.children("tie").compactMap { $0.attributes["type"] }
                        let dynamics = element.attributes["dynamics"].flatMap(Double.init)
                        let note = ParsedNote(
                            uid: nextUID, part: partIndex, staff: staff, voice: voice, pitch: spelling.midiPitch,
                            spelling: spelling, startTick: start, durationTicks: duration,
                            velocity: UInt8(clamping: Int(((dynamics ?? 88.9) * 0.9).rounded())),
                            tieStart: ties.contains("start"), tieStop: ties.contains("stop"),
                            finger: Self.finger(of: element)
                        )
                        nextUID += 1
                        measure.notes.append(note)
                        let written = WrittenPitch(
                            spelling: spelling,
                            printedAccidental: accidental(element.text(of: "accidental")),
                            tieStart: note.tieStart, tieStop: note.tieStop, noteID: note.uid
                        )
                        if isChord, let last = measure.events.indices.last, !measure.events[last].isRest {
                            measure.events[last].pitches.append(written)
                        } else {
                            var newEvent = event
                            newEvent.pitches = [written]
                            measure.events.append(newEvent)
                        }
                    } else if element.child("rest") != nil && !isChord {
                        measure.events.append(event)
                    }
                    if !isChord {
                        lastNoteStart = position
                        position += duration
                    }
                default:
                    break
                }
                maxPosition = max(maxPosition, position)
            }
            measure.length = maxPosition
            result.append(measure)
        }
        return result
    }

    private func notatedEvent(for note: XMLElementNode, start: Int, duration: Int, staff: Int, voice: Int, part: Int) -> NotatedEvent {
        var tuplet: (Int, Int)?
        if let modification = note.child("time-modification"), let actual = modification.int(of: "actual-notes"),
           let normal = modification.int(of: "normal-notes") {
            tuplet = (actual, normal)
        }
        let beams = note.children("beam")
            .sorted { (Int($0.attributes["number"] ?? "1") ?? 1) < (Int($1.attributes["number"] ?? "1") ?? 1) }
            .compactMap { BeamState(rawValue: $0.trimmedText) }
        let stem = note.text(of: "stem")
        return NotatedEvent(
            startTick: start, durationTicks: duration, measureIndex: 0, staff: staff, voice: voice,
            value: note.text(of: "type").flatMap(NoteValue.init(musicXMLName:)),
            dots: note.children("dot").count, tuplet: tuplet, pitches: [], beams: beams,
            stemUp: stem == "up" ? true : stem == "down" ? false : nil,
            track: part
        )
    }

    private func accidental(_ name: String?) -> Accidental? {
        switch name {
        case "sharp": .sharp
        case "flat": .flat
        case "natural": .natural
        case "double-sharp", "sharp-sharp": .doubleSharp
        case "flat-flat", "double-flat": .doubleFlat
        default: nil
        }
    }

    // MARK: Unrolling helpers

    /// The first finger written on a note (`<technical><fingering>`), ignoring substitutions such as "3-1".
    private static func finger(of note: XMLElementNode) -> UInt8? {
        for notations in note.children("notations") {
            for technical in notations.children("technical") {
                for fingering in technical.children("fingering") {
                    if let digit = fingering.trimmedText.first?.wholeNumberValue, (1...5).contains(digit) {
                        return UInt8(digit)
                    }
                }
            }
        }
        return nil
    }

    private func mergeTies(_ notes: [ParsedNote]) -> ([ParsedNote], [Int: Int]) {
        var result: [ParsedNote] = []
        var owner: [Int: Int] = [:] // uid → uid of the chain head
        var open: [TieKey: Int] = [:] // → index in result
        for note in notes.sorted(by: { $0.startTick < $1.startTick }) {
            let key = TieKey(part: note.part, staff: note.staff, voice: note.voice, pitch: note.pitch)
            if note.tieStop, let headIndex = open[key], result[headIndex].startTick + result[headIndex].durationTicks == note.startTick {
                result[headIndex].durationTicks += note.durationTicks
                owner[note.uid] = result[headIndex].uid
                if !note.tieStart { open[key] = nil }
                continue
            }
            owner[note.uid] = note.uid
            result.append(note)
            open[key] = note.tieStart ? result.count - 1 : nil
        }
        return (result, owner)
    }

    private func keySignatureChanges(_ changes: [(tick: Int, fifths: Int)]) -> [KeySignatureChange] {
        var result: [KeySignatureChange] = []
        for change in changes.sorted(by: { $0.tick < $1.tick }) {
            guard let key = KeySignature(fifths: change.fifths), result.last?.key != key else { continue }
            if let last = result.last, last.tick == change.tick { result.removeLast() }
            result.append(KeySignatureChange(tick: change.tick, key: key))
        }
        if !result.isEmpty { result[0].tick = 0 }
        return result
    }

    private func parseEndingNumbers(_ text: String) -> Set<Int> {
        Set(text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) })
    }

    private func leadingInt(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(String(text.prefix { $0.isNumber }))
    }
}

private struct TrackKey: Hashable, Comparable {
    var part: Int
    var staff: Int
    static func < (lhs: TrackKey, rhs: TrackKey) -> Bool { (lhs.part, lhs.staff) < (rhs.part, rhs.staff) }
}

private struct TieKey: Hashable {
    var part: Int
    var staff: Int
    var voice: Int
    var pitch: Int
}

private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
private func lcm(_ a: Int, _ b: Int) -> Int { a / gcd(a, b) * b }

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
