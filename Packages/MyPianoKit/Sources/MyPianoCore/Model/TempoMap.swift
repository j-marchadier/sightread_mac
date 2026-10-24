import Foundation

/// Converts between ticks and seconds (at 100 % speed) across tempo changes.
public struct TempoMap: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public var tick: Int
        public var microsecondsPerQuarter: Int
        /// Seconds elapsed at `tick`.
        public var seconds: TimeInterval

        public var bpm: Double { 60_000_000 / Double(microsecondsPerQuarter) }
    }

    public static let defaultMicrosecondsPerQuarter = 500_000 // 120 BPM

    public let ticksPerQuarter: Int
    public private(set) var segments: [Segment]

    /// - Parameter changes: `(tick, microseconds per quarter)` pairs in any order.
    ///   When several changes share a tick, the last one wins.
    public init(ticksPerQuarter: Int, changes: [(tick: Int, microsecondsPerQuarter: Int)] = []) {
        self.ticksPerQuarter = max(1, ticksPerQuarter)
        var byTick: [Int: Int] = [:]
        var order: [Int] = []
        for change in changes where change.microsecondsPerQuarter > 0 {
            let tick = max(0, change.tick)
            if byTick[tick] == nil { order.append(tick) }
            byTick[tick] = change.microsecondsPerQuarter
        }
        if byTick[0] == nil {
            byTick[0] = Self.defaultMicrosecondsPerQuarter
            order.append(0)
        }
        var segments: [Segment] = []
        for tick in order.sorted() {
            let tempo = byTick[tick]!
            if let last = segments.last {
                if last.microsecondsPerQuarter == tempo { continue }
                let seconds = last.seconds + Self.seconds(ticks: tick - last.tick, tempo: last.microsecondsPerQuarter, ppq: self.ticksPerQuarter)
                segments.append(Segment(tick: tick, microsecondsPerQuarter: tempo, seconds: seconds))
            } else {
                segments.append(Segment(tick: 0, microsecondsPerQuarter: tempo, seconds: 0))
            }
        }
        self.segments = segments
    }

    /// Convenience: constant tempo in beats (quarters) per minute.
    public init(ticksPerQuarter: Int, bpm: Double) {
        self.init(ticksPerQuarter: ticksPerQuarter, changes: [(0, Int((60_000_000 / bpm).rounded()))])
    }

    public func seconds(atTick tick: Int) -> TimeInterval {
        let segment = segment(containingTick: tick)
        return segment.seconds + Self.seconds(ticks: tick - segment.tick, tempo: segment.microsecondsPerQuarter, ppq: ticksPerQuarter)
    }

    /// Nearest tick at or before `seconds`.
    public func tick(atSeconds seconds: TimeInterval) -> Int {
        var index = 0
        for (i, segment) in segments.enumerated() where segment.seconds <= seconds { index = i }
        let segment = segments[index]
        let ticks = (seconds - segment.seconds) * 1_000_000 / Double(segment.microsecondsPerQuarter) * Double(ticksPerQuarter)
        return segment.tick + Int((ticks + 1e-6).rounded(.down))
    }

    /// Tempo in quarter notes per minute at a position in seconds.
    public func bpm(atSeconds seconds: TimeInterval) -> Double {
        (segments.last { $0.seconds <= seconds } ?? segments[0]).bpm
    }

    public func bpm(atTick tick: Int) -> Double {
        segment(containingTick: tick).bpm
    }

    private func segment(containingTick tick: Int) -> Segment {
        var low = 0
        var high = segments.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if segments[mid].tick <= tick { low = mid } else { high = mid - 1 }
        }
        return segments[low]
    }

    private static func seconds(ticks: Int, tempo: Int, ppq: Int) -> TimeInterval {
        Double(ticks) * Double(tempo) / 1_000_000 / Double(ppq)
    }
}
