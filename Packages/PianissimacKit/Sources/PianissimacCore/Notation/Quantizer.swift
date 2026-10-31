import Foundation

/// Guesses written rhythms for MIDI notes, one voice per staff.
///
/// 1. Each quarter-note beat gets a grid: sixteenths, or eighth-note triplets when they fit the
///    onsets in that beat clearly better.
/// 2. Onsets and ends snap to the grid; notes starting together become chords; a chord lasts until
///    its shortest note ends or the next chord starts.
/// 3. Each measure is filled with notes and rests, split into writable values (tied when needed)
///    without crossing bar lines or triplet beats.
/// 4. Beams, stems and accidentals follow common engraving rules.
struct Quantizer {
    let song: Song
    let hands: [Hand?]
    let transpose: Int
    let forcedKey: KeySignature?

    private var ppq: Int { song.ticksPerQuarter }
    private var sixteenth: Int { max(1, ppq / 4) }
    private var tripletEighth: Int? { ppq % 3 == 0 ? ppq / 3 : nil }

    func key(atTick tick: Int) -> KeySignature? {
        (forcedKey ?? song.keySignature(atTick: tick))?.transposed(by: transpose)
    }

    private struct Chord {
        var start: Int
        var end: Int
        var notes: [Note]
    }

    func build() -> RhythmicScore {
        let anyHand = hands.contains { $0 != nil }
        var perClef: [Clef: [Note]] = [:]
        for note in song.notes {
            let hand = hands.indices.contains(note.id) ? hands[note.id] : nil
            if anyHand && hand == nil { continue }
            let pitch = Int(PianoKeys.transpose(note.pitch, by: transpose))
            perClef[Clef.forNote(hand: hand, pitch: pitch), default: []].append(note)
        }

        let triplets = tripletBeats(perClef.values.flatMap { $0 })
        var events: [RhythmicScore.Event] = []
        var totalError = 0.0
        var onsetCount = 0
        for clef in Clef.allCases {
            let notes = perClef[clef] ?? []
            let (chords, error) = chords(from: notes, triplets: triplets)
            totalError += error
            onsetCount += notes.count
            events += layOut(chords, clef: clef, triplets: triplets, startID: events.count)
        }
        events.sort { ($0.startTick, $0.clef == .treble ? 0 : 1) < ($1.startTick, $1.clef == .treble ? 0 : 1) }
        for index in events.indices { events[index].id = index }
        NotationRules.assignBeams(&events, song: song)
        NotationRules.assignAccidentals(&events, key: key(atTick:))

        // Quality: average onset error relative to half a sixteenth.
        let meanError = onsetCount == 0 ? 0 : totalError / Double(onsetCount)
        let quality = max(0, min(1, 1 - meanError / (Double(sixteenth) / 2)))
        return RhythmicScore(events: events, source: .quantized, quality: quality)
    }

    // MARK: Grid

    /// Beats (index = tick / ppq) whose onsets fit eighth-note triplets much better than sixteenths.
    private func tripletBeats(_ notes: [Note]) -> Set<Int> {
        guard let triplet = tripletEighth else { return [] }
        let byBeat = Dictionary(grouping: notes, by: { $0.startTick / ppq })
        var result: Set<Int> = []
        for (beat, beatNotes) in byBeat {
            let offsets = beatNotes.map { $0.startTick - beat * ppq }
            let binaryError = offsets.reduce(0.0) { $0 + squaredDistance($1, step: sixteenth) }
            let tripletError = offsets.reduce(0.0) { $0 + squaredDistance($1, step: triplet) }
            // Binary rhythms are far more common: require a clear advantage.
            if tripletError * 3 < binaryError && offsets.contains(where: { $0 % sixteenth != 0 }) {
                result.insert(beat)
            }
        }
        return result
    }

    private func squaredDistance(_ offset: Int, step: Int) -> Double {
        let remainder = offset % step
        let distance = Double(min(remainder, step - remainder))
        return distance * distance
    }

    private func step(atBeat beat: Int, triplets: Set<Int>) -> Int {
        triplets.contains(beat) ? (tripletEighth ?? sixteenth) : sixteenth
    }

    /// Nearest grid point to `tick`, using the grid of the beat it falls in.
    private func snap(_ tick: Int, triplets: Set<Int>) -> Int {
        let beat = max(0, tick) / ppq
        let step = step(atBeat: beat, triplets: triplets)
        let offset = tick - beat * ppq
        return beat * ppq + Int((Double(offset) / Double(step)).rounded()) * step
    }

    // MARK: Chords

    private func chords(from notes: [Note], triplets: Set<Int>) -> ([Chord], Double) {
        var error = 0.0
        var byStart: [Int: [Note]] = [:]
        for note in notes {
            let start = snap(note.startTick, triplets: triplets)
            error += Double(abs(start - note.startTick))
            byStart[start, default: []].append(note)
        }
        let starts = byStart.keys.sorted()
        var chords: [Chord] = []
        for (i, start) in starts.enumerated() {
            let members = byStart[start]!
            let minimum = start + step(atBeat: start / ppq, triplets: triplets)
            var end = members.map { max(minimum, snap($0.endTick, triplets: triplets)) }.min() ?? minimum
            if i + 1 < starts.count { end = min(end, starts[i + 1]) }
            chords.append(Chord(start: start, end: max(end, start + 1), notes: members.sorted { $0.pitch < $1.pitch }))
        }
        return (chords, error)
    }

    // MARK: Measures

    private func layOut(_ chords: [Chord], clef: Clef, triplets: Set<Int>, startID: Int) -> [RhythmicScore.Event] {
        var events: [RhythmicScore.Event] = []
        var chordIndex = 0
        for (measureIndex, measure) in song.measures.enumerated() {
            var cursor = measure.startTick
            var hasNotes = false
            while chordIndex < chords.count, chords[chordIndex].end <= measure.startTick { chordIndex += 1 }
            var index = chordIndex
            while index < chords.count, chords[index].start < measure.endTick {
                let chord = chords[index]
                let partStart = max(chord.start, measure.startTick)
                let partEnd = min(chord.end, measure.endTick)
                if partStart > cursor {
                    events += pieces(from: cursor, to: partStart, measureIndex: measureIndex, clef: clef, chord: nil, tiesOut: false, triplets: triplets)
                }
                if partEnd > partStart {
                    events += pieces(from: partStart, to: partEnd, measureIndex: measureIndex, clef: clef, chord: chord,
                                     tiesOut: chord.end > measure.endTick, triplets: triplets)
                    hasNotes = true
                    cursor = partEnd
                }
                index += 1
            }
            if !hasNotes {
                events.append(rest(measureIndex: measureIndex, clef: clef, start: measure.startTick, ticks: measure.ticks, measureRest: true))
            } else if cursor < measure.endTick {
                events += pieces(from: cursor, to: measure.endTick, measureIndex: measureIndex, clef: clef, chord: nil, tiesOut: false, triplets: triplets)
            }
        }
        for i in events.indices { events[i].id = startID + i }
        return events
    }

    /// Splits `[start, end)` into writable values. Notes get ties between pieces (and after the
    /// last one when the chord continues into the next measure).
    private func pieces(
        from start: Int, to end: Int, measureIndex: Int, clef: Clef, chord: Chord?, tiesOut: Bool, triplets: Set<Int>
    ) -> [RhythmicScore.Event] {
        let measureStart = song.measures[measureIndex].startTick
        let durations = NotationRules.binaryDurations(ppq: ppq)
        var result: [RhythmicScore.Event] = []
        var t = start
        while t < end {
            let beat = t / ppq
            var length: Int
            var value: NoteValue
            var dots = 0
            var tuplet: Int?
            if triplets.contains(beat), let unit = tripletEighth {
                let pieceEnd = min(end, (beat + 1) * ppq)
                let units = max(1, (pieceEnd - t + unit / 2) / unit)
                length = min(pieceEnd - t, units * unit)
                if units >= 3 && t == beat * ppq {
                    value = .quarter
                } else if units == 2 {
                    value = .quarter
                    tuplet = 3
                } else {
                    value = .eighth
                    tuplet = 3
                    length = min(length, unit)
                }
                if length <= 0 { length = pieceEnd - t }
            } else {
                // Stay out of the next triplet beat.
                var limit = end
                var nextBeat = beat + 1
                while nextBeat * ppq < end {
                    if triplets.contains(nextBeat) { limit = nextBeat * ppq; break }
                    nextBeat += 1
                }
                let offset = t - measureStart
                let fitting = durations.first { option in
                    let base = option.dots == 1 ? option.ticks * 2 / 3 : option.ticks
                    return option.ticks <= limit - t && offset % min(base, ppq) == 0
                }
                if let fitting {
                    length = fitting.ticks
                    value = fitting.value
                    dots = fitting.dots
                } else {
                    length = limit - t
                    let nearest = NotationRules.nearestValue(ticks: length, ppq: ppq)
                    value = nearest.value
                    dots = nearest.dots
                }
            }
            let isLast = t + length >= end
            if let chord {
                let heads = chord.notes.map { note -> RhythmicScore.Head in
                    let pitch = Int(PianoKeys.transpose(note.pitch, by: transpose))
                    let spelled = Speller.spell(pitch, in: key(atTick: chord.start))
                    return RhythmicScore.Head(
                        pitch: spelled, step: StaffGeometry.step(of: spelled, clef: clef), accidental: nil,
                        tiesToNext: !isLast || tiesOut, noteID: note.id
                    )
                }
                result.append(event(measureIndex: measureIndex, clef: clef, start: t, ticks: length, value: value, dots: dots, tuplet: tuplet, heads: heads))
            } else {
                result.append(event(measureIndex: measureIndex, clef: clef, start: t, ticks: length, value: value, dots: dots, tuplet: tuplet, heads: []))
            }
            t += length
        }
        return result
    }

    private func rest(measureIndex: Int, clef: Clef, start: Int, ticks: Int, measureRest: Bool) -> RhythmicScore.Event {
        var event = event(measureIndex: measureIndex, clef: clef, start: start, ticks: ticks, value: .whole, dots: 0, tuplet: nil, heads: [])
        event.isMeasureRest = measureRest
        return event
    }

    private func event(
        measureIndex: Int, clef: Clef, start: Int, ticks: Int, value: NoteValue, dots: Int, tuplet: Int?, heads: [RhythmicScore.Head]
    ) -> RhythmicScore.Event {
        RhythmicScore.Event(
            id: 0, clef: clef, measureIndex: measureIndex, startTick: start, durationTicks: ticks,
            start: song.tempoMap.seconds(atTick: start), end: song.tempoMap.seconds(atTick: start + ticks),
            value: value, dots: dots, tuplet: tuplet, heads: heads,
            stemUp: NotationRules.stemUp(steps: heads.map(\.step)), beamGroup: nil, isMeasureRest: false
        )
    }
}
