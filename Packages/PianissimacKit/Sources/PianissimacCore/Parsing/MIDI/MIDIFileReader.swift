import Foundation

/// Reads Standard MIDI Files (formats 0 and 1).
///
/// The reader is tolerant of common defects found in real files: chunk lengths that run past
/// the end of the data, missing end-of-track events, unknown chunks and stray data bytes.
public enum MIDIFileReader {
    public static func read(_ data: Data) throws(MIDIFileError) -> MIDIFile {
        var reader = ByteReader(data)
        guard reader.readASCII(4) == "MThd", let headerLength = reader.readUInt32() else {
            throw .notAMIDIFile
        }
        guard headerLength >= 6, let format = reader.readUInt16(), let trackCount = reader.readUInt16(),
              let division = reader.readUInt16()
        else { throw .truncated }
        reader.skip(Int(headerLength) - 6)

        guard division & 0x8000 == 0 else { throw .unsupportedTimeDivision }
        guard format <= 1 else { throw .unsupportedFormat(Int(format)) }

        var tracks: [[MIDIEvent]] = []
        while tracks.count < Int(trackCount), !reader.isAtEnd {
            guard let chunkType = reader.readASCII(4), let declaredLength = reader.readUInt32() else { break }
            let length = min(Int(declaredLength), reader.remaining)
            let body = reader.readBytes(length)
            if chunkType == "MTrk" {
                tracks.append(readTrack(body))
            }
        }
        guard !tracks.isEmpty else { throw .noTracks }
        return MIDIFile(format: Int(format), ticksPerQuarter: max(1, Int(division)), tracks: tracks)
    }

    private static func readTrack(_ bytes: [UInt8]) -> [MIDIEvent] {
        var reader = ByteReader(bytes)
        var events: [MIDIEvent] = []
        var tick = 0
        var runningStatus: UInt8?

        while !reader.isAtEnd {
            guard let delta = reader.readVariableLength() else { break }
            tick += delta
            guard var status = reader.peekByte() else { break }

            if status & 0x80 != 0 {
                reader.skip(1)
            } else if let running = runningStatus {
                status = running
            } else {
                reader.skip(1) // Stray data byte without status: ignore it.
                continue
            }

            switch status {
            case 0xFF:
                guard let type = reader.readByte(), let length = reader.readVariableLength() else { return events }
                let payload = reader.readBytes(length)
                let kind = metaEvent(type: type, payload: payload)
                events.append(MIDIEvent(tick: tick, kind: kind))
                if kind == .endOfTrack { return events }
            case 0xF0, 0xF7:
                guard let length = reader.readVariableLength() else { return events }
                reader.skip(length)
                events.append(MIDIEvent(tick: tick, kind: .sysex))
            case 0x80...0xEF:
                runningStatus = status
                let channel = status & 0x0F
                let dataCount = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
                let data = reader.readBytes(dataCount)
                guard data.count == dataCount else { return events }
                events.append(MIDIEvent(tick: tick, kind: channelEvent(status: status & 0xF0, channel: channel, data: data)))
            default:
                // System common/real-time messages do not belong in files; skip the status byte.
                break
            }
        }
        return events
    }

    private static func channelEvent(status: UInt8, channel: UInt8, data: [UInt8]) -> MIDIEvent.Kind {
        switch status {
        case 0x90 where data[1] > 0: .noteOn(channel: channel, pitch: data[0] & 0x7F, velocity: data[1] & 0x7F)
        case 0x90, 0x80: .noteOff(channel: channel, pitch: data[0] & 0x7F, velocity: data[1] & 0x7F)
        case 0xB0: .controlChange(channel: channel, controller: data[0] & 0x7F, value: data[1] & 0x7F)
        case 0xC0: .programChange(channel: channel, program: data[0] & 0x7F)
        default: .otherChannelMessage(status: status | channel)
        }
    }

    private static func metaEvent(type: UInt8, payload: [UInt8]) -> MIDIEvent.Kind {
        switch type {
        case 0x51 where payload.count >= 3:
            return .tempo(microsecondsPerQuarter: Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2]))
        case 0x58 where payload.count >= 2:
            let exponent = min(Int(payload[1]), 6)
            return .timeSignature(numerator: Int(payload[0]), denominator: 1 << exponent)
        case 0x59 where payload.count >= 2:
            return .keySignature(fifths: Int(Int8(bitPattern: payload[0])), isMinor: payload[1] == 1)
        case 0x03:
            return .trackName(decodeText(payload))
        case 0x01, 0x02, 0x04, 0x05, 0x06, 0x07:
            return .text(type: type, decodeText(payload))
        case 0x2F:
            return .endOfTrack
        default:
            return .otherMeta(type: type)
        }
    }

    /// Text events have no declared encoding: try UTF-8, fall back to Latin-1, and drop NUL padding.
    private static func decodeText(_ bytes: [UInt8]) -> String {
        let trimmed = Array(bytes.prefix { $0 != 0 })
        let text = String(bytes: trimmed, encoding: .utf8) ?? String(bytes: trimmed, encoding: .isoLatin1) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Sequential big-endian reader over a byte buffer. Reads past the end return `nil` or short results.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { position >= bytes.count }
    var remaining: Int { max(0, bytes.count - position) }

    func peekByte() -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    mutating func readByte() -> UInt8? {
        guard position < bytes.count else { return nil }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func readBytes(_ count: Int) -> [UInt8] {
        let end = min(bytes.count, position + max(0, count))
        defer { position = end }
        return Array(bytes[position..<end])
    }

    mutating func skip(_ count: Int) {
        position = min(bytes.count, position + max(0, count))
    }

    mutating func readUInt16() -> UInt16? {
        let b = readBytes(2)
        return b.count == 2 ? UInt16(b[0]) << 8 | UInt16(b[1]) : nil
    }

    mutating func readUInt32() -> UInt32? {
        let b = readBytes(4)
        return b.count == 4 ? b.reduce(0) { $0 << 8 | UInt32($1) } : nil
    }

    mutating func readASCII(_ count: Int) -> String? {
        let b = readBytes(count)
        return b.count == count ? String(bytes: b, encoding: .ascii) : nil
    }

    /// MIDI variable-length quantity (at most 4 bytes).
    mutating func readVariableLength() -> Int? {
        var value = 0
        for _ in 0..<4 {
            guard let byte = readByte() else { return nil }
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        return value
    }
}
