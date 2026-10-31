import Foundation

/// Forwards keyboard events (from the MIDI thread) to whichever practice engine is open.
public final class PracticeInputRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: PracticeEngine?

    public init() {}

    public func attach(_ engine: PracticeEngine) {
        lock.lock()
        self.engine = engine
        lock.unlock()
    }

    /// Detaches `engine` if it is still the current one.
    public func detach(_ engine: PracticeEngine) {
        lock.lock()
        if self.engine === engine { self.engine = nil }
        lock.unlock()
    }

    public func handle(_ event: InputEvent) {
        lock.lock()
        let engine = self.engine
        lock.unlock()
        engine?.handle(event)
    }
}
