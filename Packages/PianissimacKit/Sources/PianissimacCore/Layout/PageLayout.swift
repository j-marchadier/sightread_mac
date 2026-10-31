import Foundation

/// Breaks a song's measures into lines ("systems") for the full-page score.
///
/// Each measure gets a width proportional to its duration (at least a minimum, so short pickup
/// measures stay readable); measures are added to a line while they fit, then the line is
/// stretched to the full width. The last line is only stretched when it is nearly full.
public struct PageLayout: Sendable, Equatable {
    public struct System: Sendable, Equatable {
        public var measures: Range<Int>
        /// Left edge of each measure, then the right edge of the last one, as fractions (0…1) of the line's music width.
        public var edges: [Double]
        /// Measure start times, then the end of the last measure.
        public var times: [TimeInterval]

        public var start: TimeInterval { times.first ?? 0 }
        public var end: TimeInterval { times.last ?? 0 }

        /// Horizontal position of a song time on this line, as a fraction of the music width.
        public func position(of time: TimeInterval) -> Double {
            guard times.count >= 2 else { return 0 }
            if time <= times[0] { return edges[0] }
            for index in 0..<(times.count - 1) where time < times[index + 1] {
                let duration = times[index + 1] - times[index]
                let fraction = duration > 0 ? (time - times[index]) / duration : 0
                return edges[index] + fraction * (edges[index + 1] - edges[index])
            }
            return edges[edges.count - 1]
        }

        /// Song time at a horizontal position (fraction of the music width) on this line.
        public func time(at position: Double) -> TimeInterval {
            guard times.count >= 2 else { return start }
            if position <= edges[0] { return times[0] }
            for index in 0..<(edges.count - 1) where position < edges[index + 1] {
                let width = edges[index + 1] - edges[index]
                let fraction = width > 0 ? (position - edges[index]) / width : 0
                return times[index] + fraction * (times[index + 1] - times[index])
            }
            return end
        }
    }

    public let systems: [System]

    /// - Parameters:
    ///   - width: width available for the music on a line, in points.
    ///   - pointsPerSecond: natural density before lines are stretched.
    ///   - minimumMeasureWidth: narrowest a measure may be, in points.
    public init(measures: [Measure], width: Double, pointsPerSecond: Double, minimumMeasureWidth: Double) {
        guard !measures.isEmpty, width > 0 else {
            systems = []
            return
        }
        let natural = measures.map { min(width, max(minimumMeasureWidth, $0.duration * pointsPerSecond)) }
        var systems: [System] = []
        var first = 0
        while first < measures.count {
            var last = first
            var used = natural[first]
            while last + 1 < measures.count, used + natural[last + 1] <= width {
                last += 1
                used += natural[last]
            }
            let isLast = last == measures.count - 1
            let scale = isLast && used < width * 0.75 ? 1 / width : 1 / used
            var edges = [0.0]
            for index in first...last { edges.append(edges[edges.count - 1] + natural[index] * scale) }
            var times = measures[first...last].map(\.start)
            times.append(measures[last].end)
            systems.append(System(measures: first..<(last + 1), edges: edges, times: times))
            first = last + 1
        }
        self.systems = systems
    }

    /// The line showing a song time.
    public func systemIndex(at time: TimeInterval) -> Int {
        guard !systems.isEmpty else { return 0 }
        return systems.lastIndex { $0.start <= time } ?? 0
    }
}
