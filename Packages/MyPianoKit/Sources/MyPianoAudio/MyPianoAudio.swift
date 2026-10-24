// AVAudioEngine output: piano samplers, metronome click, latency.
// Apple-only module: it compiles to an empty module on other platforms.
#if canImport(AVFAudio)
import MyPianoCore

public enum MyPianoAudioModule {}
#endif
