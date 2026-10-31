import Foundation

/// Keys currently held on the player's keyboard, readable from any thread (the renderer reads it
/// every frame while the MIDI thread updates it).
public final class PressedKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [UInt8: TimeInterval] = [:]

    public init() {}

    public func apply(_ event: InputEvent) {
        lock.lock()
        switch event.kind {
        case let .noteOn(pitch, _): keys[pitch] = event.time
        case let .noteOff(pitch): keys[pitch] = nil
        case .sustain: break
        }
        lock.unlock()
    }

    /// Pitches held, with the host time each was pressed.
    public var current: [UInt8: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }

    public func releaseAll() {
        lock.lock()
        keys.removeAll()
        lock.unlock()
    }
}
