import Foundation
import MyPianoAudio
import MyPianoCore
import MyPianoMIDI
import Observation

/// One keyboard event shown in the diagnostics window.
struct KeyboardEventRecord: Identifiable {
    let id = UUID()
    let event: InputEvent
    let receivedAt = Date()
}

/// Application-wide services: MIDI input, audio output and their wiring.
@MainActor
@Observable
final class AppModel {
    let midi = MIDIService()
    let audio = PianoAudioEngine()
    @ObservationIgnored let latency = LatencyMonitor()

    private(set) var recentEvents: [KeyboardEventRecord] = []
    private(set) var pressedPitches: Set<UInt8> = []
    private(set) var isSustainDown = false
    private(set) var audioState: PianoAudioEngine.State = .stopped
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        audio.start()
        audioState = audio.state

        let audio = self.audio
        let latency = self.latency
        midi.setEventHandler { [weak self] event in
            // On CoreMIDI's thread: sound first, bookkeeping after.
            audio.playerPiano.handle(event)
            if case .noteOn = event.kind {
                latency.record(HostTime.now - event.time)
            }
            let model = self
            Task { @MainActor in model?.record(event) }
        }
        midi.start()
    }

    func restartAudio() {
        audio.stop()
        audio.start()
        audioState = audio.state
    }

    private func record(_ event: InputEvent) {
        switch event.kind {
        case let .noteOn(pitch, _): pressedPitches.insert(pitch)
        case let .noteOff(pitch): pressedPitches.remove(pitch)
        case let .sustain(isDown): isSustainDown = isDown
        }
        recentEvents.insert(KeyboardEventRecord(event: event), at: 0)
        if recentEvents.count > 12 { recentEvents.removeLast(recentEvents.count - 12) }
    }
}
