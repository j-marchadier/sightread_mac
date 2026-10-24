#if canImport(AVFAudio)
import AudioToolbox
import AVFAudio
import Foundation
import MyPianoCore
import os

/// Audio output of MyPiano: two pianos (the song and the player) and a click generator.
///
/// The player's piano is separate from the song's so the same key played by both never cuts
/// itself off, and each has its own volume. Every method can be called from any thread;
/// key presses are forwarded straight from the MIDI thread to keep latency low.
public final class PianoAudioEngine: @unchecked Sendable {
    public enum State: Sendable, Equatable {
        case stopped
        case running
        case failed(String)
    }

    /// Piano answering the player's keys.
    public let playerPiano: PianoSampler
    /// Piano playing the song.
    public let songPiano: PianoSampler

    private let engine = AVAudioEngine()
    private let clicks = ClickRenderer()
    private var clickNode: AVAudioSourceNode?
    private let lock = NSLock()
    private var _state: State = .stopped
    private var configurationObserver: NSObjectProtocol?

    /// Requested output buffer, in frames. 128 frames ≈ 2.7 ms at 48 kHz.
    public static let preferredBufferFrames: UInt32 = 128

    public init() {
        playerPiano = PianoSampler()
        songPiano = PianoSampler()
    }

    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    private func setState(_ state: State) {
        lock.lock()
        _state = state
        lock.unlock()
    }

    /// Builds the audio graph, loads the piano and starts the engine.
    public func start() {
        if state == .running { return }
        do {
            try buildGraphIfNeeded()
            setPreferredBufferSize(Self.preferredBufferFrames)
            engine.prepare()
            try engine.start()
            try loadPiano()
            setState(.running)
        } catch {
            setState(.failed(error.localizedDescription))
        }
        observeConfigurationChanges()
    }

    public func stop() {
        allNotesOff()
        engine.stop()
        setState(.stopped)
    }

    /// Plays a synthesized click (metronome, count-in) or the wrong-note cue.
    public func playClick(_ sound: ClickSound, gain: Float = 1) {
        clicks.trigger(sound, gain: gain)
    }

    /// Volume of everything the app plays, on top of each instrument's own volume.
    public var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    public var clickVolume: Float {
        get { clickNode?.volume ?? 1 }
        set { clickNode?.volume = max(0, min(1, newValue)) }
    }

    public func allNotesOff() {
        playerPiano.allNotesOff()
        songPiano.allNotesOff()
    }

    /// Estimated delay between asking for a sound and hearing it: output buffer plus device latency.
    public var estimatedOutputLatency: TimeInterval {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let frames = currentBufferSize() ?? Self.preferredBufferFrames
        let buffer = sampleRate > 0 ? Double(frames) / sampleRate : 0
        return buffer + engine.outputNode.presentationLatency
    }

    public var sampleRate: Double { engine.outputNode.outputFormat(forBus: 0).sampleRate }

    // MARK: Graph

    private func buildGraphIfNeeded() throws {
        guard clickNode == nil else { return }
        let mixer = engine.mainMixerNode
        for piano in [songPiano, playerPiano] {
            engine.attach(piano.unit)
            engine.connect(piano.unit, to: mixer, format: nil)
        }
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 48_000, channels: 1)!
        clicks.configure(sampleRate: format.sampleRate)
        let renderer = clicks
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            isSilence.pointee = ObjCBool(!renderer.render(frameCount: Int(frameCount), into: audioBufferList))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
        clickNode = node
    }

    /// Loads a piano into both samplers: a bundled `Piano.sf2` if present, otherwise the
    /// General MIDI bank that ships with macOS (program 0, acoustic grand piano).
    private func loadPiano() throws {
        let bundled = Bundle.main.url(forResource: "Piano", withExtension: "sf2")
        let system = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        guard let bank = bundled ?? (FileManager.default.fileExists(atPath: system.path) ? system : nil) else {
            throw PianoAudioError.soundBankNotFound
        }
        for piano in [songPiano, playerPiano] {
            try piano.load(soundBank: bank)
        }
    }

    private func setPreferredBufferSize(_ frames: UInt32) {
        guard let unit = engine.outputNode.audioUnit else { return }
        var value = frames
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout<UInt32>.size))
    }

    private func currentBufferSize() -> UInt32? {
        guard let unit = engine.outputNode.audioUnit else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &value, &size)
        return status == noErr ? value : nil
    }

    /// Output device changes (headphones plugged in, display audio…) stop the engine: restart it.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.setState(.stopped)
            self.start()
        }
    }
}

public enum PianoAudioError: LocalizedError {
    case soundBankNotFound

    public var errorDescription: String? {
        switch self {
        case .soundBankNotFound: String(localized: "Aucune banque de sons de piano n'a été trouvée.")
        }
    }
}

/// One General MIDI piano. Thread-safe: AUSampler accepts MIDI from any thread.
public final class PianoSampler: NoteOutput, @unchecked Sendable {
    let unit = AVAudioUnitSampler()
    private let channel: UInt8 = 0

    public var volume: Float {
        get { unit.volume }
        set { unit.volume = max(0, min(1, newValue)) }
    }

    func load(soundBank url: URL) throws {
        try unit.loadSoundBankInstrument(
            at: url, program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
    }

    public func noteOn(_ pitch: UInt8, velocity: UInt8) {
        unit.startNote(pitch & 0x7F, withVelocity: max(1, velocity & 0x7F), onChannel: channel)
    }

    public func noteOff(_ pitch: UInt8) {
        unit.stopNote(pitch & 0x7F, onChannel: channel)
    }

    public func setSustain(_ isDown: Bool) {
        unit.sendController(64, withValue: isDown ? 127 : 0, onChannel: channel)
    }

    public func allNotesOff() {
        setSustain(false)
        for pitch in UInt8(0)...127 { unit.stopNote(pitch, onChannel: channel) }
    }

    /// Plays a keyboard event as it arrives.
    public func handle(_ event: InputEvent) {
        switch event.kind {
        case let .noteOn(pitch, velocity): noteOn(pitch, velocity: velocity)
        case let .noteOff(pitch): noteOff(pitch)
        case let .sustain(isDown): setSustain(isDown)
        }
    }
}

/// Renders clicks on the audio thread; triggers come from any thread.
final class ClickRenderer: @unchecked Sendable {
    private let synth = OSAllocatedUnfairLock(initialState: ClickSynthesizer(sampleRate: 48_000))

    func configure(sampleRate: Double) {
        synth.withLock { $0 = ClickSynthesizer(sampleRate: sampleRate) }
    }

    func trigger(_ sound: ClickSound, gain: Float) {
        synth.withLock { $0.trigger(sound, gain: gain) }
    }

    /// Fills the buffers; returns `false` when the output is silent.
    func render(frameCount: Int, into list: UnsafeMutablePointer<AudioBufferList>) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return false }
        // Never block the audio thread: skip this cycle if a trigger holds the lock.
        let rendered = synth.withLockIfAvailableUnchecked { synth -> Bool in
            guard !synth.isSilent else { return false }
            synth.render(into: first, frameCount: frameCount)
            return true
        } ?? false
        if rendered {
            for buffer in buffers.dropFirst() {
                if let data = buffer.mData { memcpy(data, first, frameCount * MemoryLayout<Float>.size) }
            }
        }
        return rendered
    }
}
#endif
