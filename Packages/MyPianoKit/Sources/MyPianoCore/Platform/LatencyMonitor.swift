import Foundation

/// Rolling statistics of the delay between a key press (hardware timestamp) and the moment the
/// sound was requested. Thread-safe: `record` is called from the MIDI thread.
public final class LatencyMonitor: @unchecked Sendable {
    public struct Summary: Sendable, Equatable {
        public var count: Int
        public var average: TimeInterval
        public var maximum: TimeInterval
        public var last: TimeInterval
    }

    private let lock = NSLock()
    private var samples: [TimeInterval]
    private var next = 0
    private var filled = 0
    private var last: TimeInterval = 0

    public init(capacity: Int = 200) {
        samples = [TimeInterval](repeating: 0, count: max(1, capacity))
    }

    public func record(_ delay: TimeInterval) {
        let value = max(0, delay)
        lock.lock()
        samples[next] = value
        next = (next + 1) % samples.count
        filled = min(filled + 1, samples.count)
        last = value
        lock.unlock()
    }

    public func summary() -> Summary? {
        lock.lock()
        defer { lock.unlock() }
        guard filled > 0 else { return nil }
        let values = samples.prefix(filled)
        return Summary(count: filled, average: values.reduce(0, +) / Double(filled), maximum: values.max() ?? 0, last: last)
    }

    public func reset() {
        lock.lock()
        next = 0
        filled = 0
        last = 0
        lock.unlock()
    }
}
