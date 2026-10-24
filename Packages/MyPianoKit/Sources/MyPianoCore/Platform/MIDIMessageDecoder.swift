import Foundation

/// Decodes incoming MIDI into ``InputEvent``s. Only what a piano needs is kept:
/// note on/off and the sustain pedal (CC 64). Everything else is ignored.
public enum MIDIMessageDecoder {
    /// Decodes Universal MIDI Packet words carrying MIDI 1.0 channel voice messages (message type 0x2).
    public static func decode(umpWords words: [UInt32], time: TimeInterval) -> [InputEvent] {
        var events: [InputEvent] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let messageType = Int(word >> 28)
            if messageType == 0x2 {
                let status = UInt8(truncatingIfNeeded: word >> 16)
                let data1 = UInt8(truncatingIfNeeded: word >> 8) & 0x7F
                let data2 = UInt8(truncatingIfNeeded: word) & 0x7F
                if let event = event(status: status, data1: data1, data2: data2, time: time) {
                    events.append(event)
                }
            }
            index += packetLength(messageType: messageType)
        }
        return events
    }

    /// Decodes a MIDI 1.0 byte stream (with running status).
    public static func decode(bytes: [UInt8], time: TimeInterval) -> [InputEvent] {
        var events: [InputEvent] = []
        var status: UInt8?
        var data: [UInt8] = []
        for byte in bytes {
            if byte >= 0xF8 { continue } // real-time messages may appear anywhere
            if byte & 0x80 != 0 {
                status = byte < 0xF0 ? byte : nil
                data.removeAll()
                continue
            }
            guard let current = status else { continue }
            data.append(byte)
            let needed = (current & 0xF0 == 0xC0 || current & 0xF0 == 0xD0) ? 1 : 2
            if data.count == needed {
                if let event = event(status: current, data1: data[0], data2: needed == 2 ? data[1] : 0, time: time) {
                    events.append(event)
                }
                data.removeAll()
            }
        }
        return events
    }

    private static func event(status: UInt8, data1: UInt8, data2: UInt8, time: TimeInterval) -> InputEvent? {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x90 where data2 > 0: return InputEvent(kind: .noteOn(pitch: data1, velocity: data2), time: time, channel: channel)
        case 0x90, 0x80: return InputEvent(kind: .noteOff(pitch: data1), time: time, channel: channel)
        case 0xB0 where data1 == 64: return InputEvent(kind: .sustain(isDown: data2 >= 64), time: time, channel: channel)
        default: return nil
        }
    }

    /// Number of 32-bit words in a UMP, by message type.
    private static func packetLength(messageType: Int) -> Int {
        switch messageType {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }
}
