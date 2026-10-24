import Foundation
import Testing
@testable import MyPianoCore

@Suite("MIDI input decoding")
struct MIDIMessageDecoderTests {
    @Test func decodesUniversalMIDIPackets() {
        let words: [UInt32] = [
            0x2090_3C64, // note on C4, velocity 100, channel 0
            0x2080_3C40, // note off
            0x2091_4000, // note on with velocity 0 = note off, channel 1
            0x20B0_407F, // sustain down
            0x20B0_4000, // sustain up
            0x20B0_0740, // volume: ignored
            0x10F8_0000, // system real-time: ignored
            0x4090_3C00, 0xFFFF_0000, // MIDI 2.0 note on (two words): ignored, but skipped correctly
            0x20E0_0000, // pitch bend: ignored
            0x2095_4850, // note on C5 channel 5
        ]
        let events = MIDIMessageDecoder.decode(umpWords: words, time: 12.5)
        #expect(events.map(\.kind) == [
            .noteOn(pitch: 60, velocity: 100), .noteOff(pitch: 60), .noteOff(pitch: 64),
            .sustain(isDown: true), .sustain(isDown: false), .noteOn(pitch: 72, velocity: 80),
        ])
        #expect(events.allSatisfy { $0.time == 12.5 })
        #expect(events.last?.channel == 5)
    }

    @Test func decodesByteStreamsWithRunningStatus() {
        let bytes: [UInt8] = [0x90, 60, 100, 64, 90, 0xF8, 60, 0, 0xB0, 64, 127, 0xC0, 5, 0x80, 64, 0]
        #expect(MIDIMessageDecoder.decode(bytes: bytes, time: 0).map(\.kind) == [
            .noteOn(pitch: 60, velocity: 100), .noteOn(pitch: 64, velocity: 90), .noteOff(pitch: 60),
            .sustain(isDown: true), .noteOff(pitch: 64),
        ])
    }
}

@Suite("MIDI source selection")
struct MIDISourcePolicyTests {
    // The four ports of an Arturia KeyLab Essential 61 mk3, as listed by macOS.
    let keyLab = [
        MIDISourceDescriptor(id: 1, name: "KL Essential 61 mk3 MIDI", manufacturer: "Arturia"),
        MIDISourceDescriptor(id: 2, name: "KL Essential 61 mk3 DINTHRU", manufacturer: "Arturia"),
        MIDISourceDescriptor(id: 3, name: "KL Essential 61 mk3 MCU/HUI", manufacturer: "Arturia"),
        MIDISourceDescriptor(id: 4, name: "KL Essential 61 mk3 ALV", manufacturer: "Arturia"),
    ]

    @Test func automaticSelectionKeepsOnlyTheKeyboardPort() {
        #expect(MIDISourcePolicy.sourcesToConnect(available: keyLab, selection: .automatic).map(\.id) == [1])
    }

    @Test func ignoresVirtualAndThroughPorts() {
        let others = [
            MIDISourceDescriptor(id: 10, name: "IAC Driver Bus 1"),
            MIDISourceDescriptor(id: 11, name: "Network Session 1"),
            MIDISourceDescriptor(id: 12, name: "MIDI Through Port-0"),
            MIDISourceDescriptor(id: 13, name: "Digital Piano"),
            MIDISourceDescriptor(id: 14, name: "Halvorsen Keys"), // "alv" inside a word is fine
        ]
        #expect(MIDISourcePolicy.sourcesToConnect(available: others, selection: .automatic).map(\.id) == [13, 14])
    }

    @Test func manualSelectionAndOfflineSources() {
        var sources = keyLab
        sources[0].isOffline = true
        #expect(MIDISourcePolicy.sourcesToConnect(available: sources, selection: .manual([1, 4])).map(\.id) == [4])
        #expect(MIDISourcePolicy.sourcesToConnect(available: sources, selection: .automatic).isEmpty)
        #expect(MIDIConnectionStatus(connected: []) == .noKeyboard)
        #expect(MIDIConnectionStatus(connected: [keyLab[0]]).isConnected)
    }

    @Test func selectionIsCodable() throws {
        for selection in [MIDIInputSelection.automatic, .manual([3, 1])] {
            let data = try JSONEncoder().encode(selection)
            #expect(try JSONDecoder().decode(MIDIInputSelection.self, from: data) == selection)
        }
    }
}

@Suite("Synthesized clicks")
struct ClickSynthesizerTests {
    @Test func clicksAreShortAudibleAndDecay() {
        var synth = ClickSynthesizer(sampleRate: 48_000)
        #expect(synth.isSilent)
        synth.trigger(.accent)
        let samples = synth.render(frameCount: 4_800) // 100 ms
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.3 && peak <= 1)
        let early = samples[0..<480].map(abs).max() ?? 0
        let late = samples[2_400..<2_880].map(abs).max() ?? 0
        #expect(late < early / 10)
        #expect(synth.isSilent) // 60 ms click finished within 100 ms
    }

    @Test func overlappingVoicesMixAndGainScales() {
        var loud = ClickSynthesizer(sampleRate: 44_100)
        loud.trigger(.beat, gain: 1)
        var soft = ClickSynthesizer(sampleRate: 44_100)
        soft.trigger(.beat, gain: 0.25)
        let a = loud.render(frameCount: 256).map(abs).max()!
        let b = soft.render(frameCount: 256).map(abs).max()!
        #expect(abs(b - a / 4) < 0.01)

        var many = ClickSynthesizer(sampleRate: 44_100)
        for _ in 0..<20 { many.trigger(.wrongNote) }
        _ = many.render(frameCount: 64)
        #expect(!many.isSilent)
        _ = many.render(frameCount: 44_100)
        #expect(many.isSilent)
    }

    @Test func hostTimeRoundTrips() {
        let seconds = 1234.5678
        #expect(abs(HostTime.seconds(fromHostTicks: HostTime.hostTicks(fromSeconds: seconds)) - seconds) < 1e-6)
        let a = HostTime.now
        let b = HostTime.now
        #expect(b >= a)
    }
}

@Suite("Latency statistics")
struct LatencyMonitorTests {
    @Test func summarizesTheLatestSamples() {
        let monitor = LatencyMonitor(capacity: 3)
        #expect(monitor.summary() == nil)
        for delay in [0.001, 0.002, 0.003, 0.010] { monitor.record(delay) } // the first one falls out
        let summary = try! #require(monitor.summary())
        #expect(summary.count == 3)
        #expect(abs(summary.average - 0.005) < 1e-12)
        #expect(summary.maximum == 0.010 && summary.last == 0.010)
        monitor.reset()
        #expect(monitor.summary() == nil)
    }
}
