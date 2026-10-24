import AppKit
import Foundation
import MyPianoAudio
import MyPianoCore
import MyPianoMIDI
import Observation
import SwiftUI

/// One keyboard event shown in the keyboard settings.
struct KeyboardEventRecord: Identifiable {
    let id = UUID()
    let event: InputEvent
    let receivedAt = Date()
}

/// Application-wide services: library, MIDI input, audio output and their wiring.
@MainActor
@Observable
final class AppModel {
    let library = LibraryModel()
    let midi = MIDIService()
    let audio = PianoAudioEngine()
    @ObservationIgnored let latency = LatencyMonitor()
    /// Delivers keyboard events to the practice session currently open.
    @ObservationIgnored let practiceInput = PracticeInputRouter()
    /// Keys held right now, read by the renderers every frame.
    @ObservationIgnored let pressedKeys = PressedKeys()
    /// Notes played recently, for free play.
    @ObservationIgnored let liveNotes = LiveNoteRecorder()

    private(set) var recentEvents: [KeyboardEventRecord] = []
    private(set) var isSustainDown = false
    private(set) var audioState: PianoAudioEngine.State = .stopped
    /// Volume of everything the app plays.
    var masterVolume = Preferences.volume(PreferenceKey.masterVolume) {
        didSet { audio.masterVolume = masterVolume; Preferences.setVolume(masterVolume, PreferenceKey.masterVolume) }
    }
    /// Volume of the notes played on the keyboard.
    var playerVolume = Preferences.volume(PreferenceKey.playerVolume) {
        didSet { audio.playerPiano.volume = playerVolume; Preferences.setVolume(playerVolume, PreferenceKey.playerVolume) }
    }
    /// Volume of the song (accompaniment and, in Learn and Listen modes, the practised part).
    var songVolume = Preferences.volume(PreferenceKey.songVolume) {
        didSet { audio.songPiano.volume = songVolume; Preferences.setVolume(songVolume, PreferenceKey.songVolume) }
    }
    /// Octave shift of the computer keyboard when it is used as a piano.
    private(set) var computerKeyboardOctave = 0
    /// Opens windows from outside a view (files opened from the Finder); set by the main window.
    @ObservationIgnored var openWindowAction: OpenWindowAction?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var heldComputerKeys: [UInt16: UInt8] = [:]

    func start() {
        guard !isStarted else { return }
        isStarted = true
        audio.playerPiano.volume = playerVolume
        audio.songPiano.volume = songVolume
        audio.start()
        audio.masterVolume = masterVolume
        audioState = audio.state

        let audio = self.audio
        let latency = self.latency
        let practiceInput = self.practiceInput
        let pressedKeys = self.pressedKeys
        let liveNotes = self.liveNotes
        midi.setEventHandler { [weak self] event in
            // On CoreMIDI's thread: sound first, then judging, bookkeeping last.
            audio.playerPiano.handle(event)
            pressedKeys.apply(event)
            liveNotes.apply(event)
            if case .noteOn = event.kind {
                latency.record(HostTime.now - event.time)
            }
            practiceInput.handle(event)
            let model = self
            Task { @MainActor in model?.record(event) }
        }
        midi.start()
        installComputerKeyboard()
    }

    /// Files opened from the Finder or dropped on the Dock icon: imported, and played when there is just one.
    func openFiles(_ urls: [URL]) {
        let result = library.importAndReport(urls)
        if let id = result.singleSongID {
            openWindowAction?(id: WindowID.player, value: PlayerTarget.song(id: id))
        } else {
            openWindowAction?(id: WindowID.main)
        }
    }

    func restartAudio() {
        audio.stop()
        audio.start()
        audio.masterVolume = masterVolume
        audioState = audio.state
    }

    /// A key played with the mouse or the computer keyboard.
    func playKey(_ pitch: UInt8, isDown: Bool, velocity: UInt8 = 80) {
        let event = InputEvent(kind: isDown ? .noteOn(pitch: pitch, velocity: velocity) : .noteOff(pitch: pitch), time: HostTime.now)
        audio.playerPiano.handle(event)
        pressedKeys.apply(event)
        liveNotes.apply(event)
        practiceInput.handle(event)
        record(event)
    }

    private func record(_ event: InputEvent) {
        if case let .sustain(isDown) = event.kind { isSustainDown = isDown }
        recentEvents.insert(KeyboardEventRecord(event: event), at: 0)
        if recentEvents.count > 12 { recentEvents.removeLast(recentEvents.count - 12) }
    }

    // MARK: Computer keyboard as a piano

    /// Physical key positions (so AZERTY and QWERTY layouts play the same notes):
    /// bottom row Z X C V B N M = C3…B3 with S D G H J for the black keys,
    /// top row Q W E R T Y U = C4…B4 with 2 3 5 6 7. ↑ and ↓ shift by an octave.
    private static let keyCodePitches: [UInt16: UInt8] = [
        6: 48, 1: 49, 7: 50, 2: 51, 8: 52, 9: 53, 5: 54, 11: 55, 4: 56, 45: 57, 38: 58, 46: 59,
        12: 60, 19: 61, 13: 62, 20: 63, 14: 64, 15: 65, 23: 66, 17: 67, 22: 68, 16: 69, 26: 70, 32: 71,
    ]

    private func installComputerKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, Preferences.computerKeyboardPiano else { return event }
            return self.handleComputerKey(event) ? nil : event
        }
    }

    /// Returns `true` when the key was used as a piano key.
    private func handleComputerKey(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        if NSApp.keyWindow?.firstResponder is NSText { return false } // typing in a text field
        if event.type == .keyDown && (event.keyCode == 126 || event.keyCode == 125) { // ↑ ↓
            computerKeyboardOctave = max(-3, min(3, computerKeyboardOctave + (event.keyCode == 126 ? 1 : -1)))
            return true
        }
        guard let base = Self.keyCodePitches[event.keyCode] else { return false }
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return true }
            let pitch = UInt8(clamping: Int(base) + computerKeyboardOctave * 12)
            heldComputerKeys[event.keyCode] = pitch
            playKey(pitch, isDown: true)
        case .keyUp:
            if let pitch = heldComputerKeys.removeValue(forKey: event.keyCode) { playKey(pitch, isDown: false) }
        default:
            return false
        }
        return true
    }
}
