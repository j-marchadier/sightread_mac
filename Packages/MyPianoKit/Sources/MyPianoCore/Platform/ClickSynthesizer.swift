import Foundation

/// Short synthesized sounds: metronome clicks and the wrong-note cue. No audio file needed.
public enum ClickSound: Sendable, CaseIterable {
    case beat
    case accent
    case wrongNote

    var frequency: Double {
        switch self {
        case .beat: 1_760
        case .accent: 2_640
        case .wrongNote: 196
        }
    }

    /// Time for the envelope to fall to 1/e, in seconds.
    var decay: Double {
        switch self {
        case .beat, .accent: 0.012
        case .wrongNote: 0.045
        }
    }

    var length: Double {
        switch self {
        case .beat, .accent: 0.06
        case .wrongNote: 0.18
        }
    }

    var level: Float {
        switch self {
        case .beat: 0.5
        case .accent: 0.75
        case .wrongNote: 0.25
        }
    }
}

/// Mixes up to a few overlapping click voices into a mono buffer. Real-time safe: no allocation
/// while rendering. Not thread-safe by itself; the audio module guards it with a lock.
public struct ClickSynthesizer: Sendable {
    private struct Voice: Sendable {
        var sound: ClickSound
        var gain: Float
        var frame: Int
    }

    public let sampleRate: Double
    private var voices: [Voice] = []
    private let maximumVoices = 8

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voices.reserveCapacity(maximumVoices)
    }

    public var isSilent: Bool { voices.isEmpty }

    public mutating func trigger(_ sound: ClickSound, gain: Float = 1) {
        if voices.count == maximumVoices { voices.removeFirst() }
        voices.append(Voice(sound: sound, gain: max(0, min(1, gain)), frame: 0))
    }

    /// Adds `frameCount` samples to `buffer`.
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard !voices.isEmpty else { return }
        for v in voices.indices {
            let sound = voices[v].sound
            let total = Int(sound.length * sampleRate)
            let gain = voices[v].gain * sound.level
            var frame = voices[v].frame
            for i in 0..<frameCount where frame < total {
                let t = Double(frame) / sampleRate
                let envelope = Float(exp(-t / sound.decay))
                let phase = 2 * Double.pi * sound.frequency * t
                var sample = Float(sin(phase))
                if sound == .wrongNote {
                    // A soft buzz: add odd harmonics for a duller, "wrong" timbre.
                    sample = Float(sin(phase) + sin(3 * phase) / 3 + sin(5 * phase) / 5) * 0.8
                }
                buffer[i] += sample * envelope * gain
                frame += 1
            }
            voices[v].frame = frame
        }
        voices.removeAll { $0.frame >= Int($0.sound.length * sampleRate) }
    }

    /// Convenience for tests and offline use.
    public mutating func render(frameCount: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: frameCount)
        buffer.withUnsafeMutableBufferPointer { render(into: $0.baseAddress!, frameCount: frameCount) }
        return buffer
    }
}
