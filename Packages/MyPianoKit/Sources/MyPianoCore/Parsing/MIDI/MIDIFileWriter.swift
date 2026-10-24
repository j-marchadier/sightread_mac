import Foundation

/// Writes a ``Song`` as a format 1 Standard MIDI File: a conductor track (tempo, meter, key)
/// followed by one track per song track.
public enum MIDIFileWriter {
    public static func data(for song: Song) -> Data {
        var chunks: [[UInt8]] = []

        var conductor: [(tick: Int, order: Int, bytes: [UInt8])] = []
        for segment in song.tempoMap.segments {
            let t = segment.microsecondsPerQuarter
            conductor.append((segment.tick, 0, [0xFF, 0x51, 0x03, UInt8(t >> 16 & 0xFF), UInt8(t >> 8 & 0xFF), UInt8(t & 0xFF)]))
        }
        for change in song.timeSignatures {
            let exponent = UInt8(max(0, Int(log2(Double(change.signature.denominator)).rounded())))
            conductor.append((change.tick, 1, [0xFF, 0x58, 0x04, UInt8(clamping: change.signature.numerator), exponent, 24, 8]))
        }
        for change in song.keySignatures {
            conductor.append((change.tick, 2, [0xFF, 0x59, 0x02, UInt8(bitPattern: Int8(change.key.fifths)), 0]))
        }
        chunks.append(trackChunk(conductor))

        for (index, track) in song.tracks.enumerated() {
            let channel = track.channel ?? defaultChannel(for: index)
            var events: [(tick: Int, order: Int, bytes: [UInt8])] = []
            if let name = track.name, !name.isEmpty {
                let text = Array(name.utf8)
                events.append((0, 0, [0xFF, 0x03] + variableLength(text.count) + text))
            }
            if let program = track.program {
                events.append((0, 1, [0xC0 | channel, program & 0x7F]))
            }
            for note in song.notes where note.track == index {
                events.append((note.startTick, 4, [0x90 | channel, note.pitch & 0x7F, max(1, note.velocity & 0x7F)]))
                // A zero-length note must still be switched off after it is switched on.
                events.append((note.endTick, note.durationTicks == 0 ? 5 : 3, [0x80 | channel, note.pitch & 0x7F, 0x40]))
            }
            for change in song.sustainChanges where change.track == index {
                events.append((change.tick, 2, [0xB0 | channel, 64, change.isDown ? 127 : 0]))
            }
            chunks.append(trackChunk(events))
        }

        var bytes: [UInt8] = Array("MThd".utf8) + uint32(6) + uint16(1) + uint16(chunks.count) + uint16(song.ticksPerQuarter)
        for chunk in chunks { bytes += chunk }
        return Data(bytes)
    }

    /// Channels 0…15 in order, skipping the percussion channel 9.
    private static func defaultChannel(for index: Int) -> UInt8 {
        let melodic: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15]
        return melodic[index % melodic.count]
    }

    /// Sorts by tick, then by `order` so note-offs precede note-ons at the same tick.
    private static func trackChunk(_ events: [(tick: Int, order: Int, bytes: [UInt8])]) -> [UInt8] {
        var body: [UInt8] = []
        var previous = 0
        for event in events.enumerated().sorted(by: { ($0.element.tick, $0.element.order, $0.offset) < ($1.element.tick, $1.element.order, $1.offset) }).map(\.element) {
            body += variableLength(event.tick - previous) + event.bytes
            previous = event.tick
        }
        body += [0x00, 0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + uint32(body.count) + body
    }

    static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(0, value)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}
