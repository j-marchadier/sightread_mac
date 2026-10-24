// CoreMIDI input: sources, hot plug, timestamped note and pedal events.
// Apple-only module: it compiles to an empty module on other platforms.
#if canImport(CoreMIDI)
import MyPianoCore

public enum MyPianoMIDIModule {}
#endif
