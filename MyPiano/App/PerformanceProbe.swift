#if DEBUG || PERF_PROBE
import AppKit
import MyPianoCore
import MyPianoRendering
import QuartzCore

/// Measures how evenly the player draws its frames, then quits. Development tool, compiled in Debug
/// (or with the PERF_PROBE condition) and enabled by environment variables only:
///
///     MYPIANO_PERF_SONG=builtin.rondo-alla-turca   library id of the song to play (in Listen mode)
///     MYPIANO_PERF_VIEW=falling|simplified|rhythmic|page
///     MYPIANO_PERF_SECONDS=10                      measured duration, after one second of warm-up
@MainActor
final class PerformanceProbe {
    static let shared: PerformanceProbe? = PerformanceProbe(environment: ProcessInfo.processInfo.environment)

    let songID: String
    let visualization: Visualization
    private let duration: TimeInterval
    private var frames: [CFTimeInterval] = []
    private var bodies = 0
    private var startedAt: CFTimeInterval?
    private var hasOpened = false

    private init?(environment: [String: String]) {
        guard let songID = environment["MYPIANO_PERF_SONG"] else { return nil }
        self.songID = songID
        visualization = switch environment["MYPIANO_PERF_VIEW"] {
        case "simplified": .simplifiedSheet
        case "rhythmic": .rhythmicSheet
        case "page": .pageSheet
        default: .fallingNotes
        }
        duration = environment["MYPIANO_PERF_SECONDS"].flatMap(Double.init) ?? 10
    }

    /// Whether the player window still has to be opened: the main window may appear more than once.
    func shouldOpenPlayer() -> Bool {
        defer { hasOpened = true }
        return !hasOpened
    }

    /// Plays the song in the probed visualization.
    func configure(_ player: PlayerViewModel) {
        // Leave the song's saved settings and history untouched.
        player.onSettingsChanged = nil
        player.onSessionEnded = nil
        player.update {
            $0.mode = .listen
            $0.countdownEnabled = false
        }
        player.updateDisplay { $0.visualization = visualization }
        Task {
            try? await Task.sleep(for: .seconds(1))
            player.togglePlayback()
            try? await Task.sleep(for: .seconds(1))
            startedAt = CACurrentMediaTime()
            RenderingDiagnostics.onDraw = { [weak self] in self?.frameDrawn() }
            try? await Task.sleep(for: .seconds(duration))
            report()
        }
    }

    /// Called once per frame the visualization actually draws.
    func frameDrawn() {
        if startedAt != nil { frames.append(CACurrentMediaTime()) }
    }

    /// Called on every evaluation of the player view's body.
    func bodyEvaluated() {
        if startedAt != nil { bodies += 1 }
    }

    private func report() {
        let intervals = zip(frames.dropFirst(), frames).map { ($0 - $1) * 1000 }.sorted()
        guard !intervals.isEmpty, let startedAt else { exit(1) }
        let elapsed = CACurrentMediaTime() - startedAt
        func percentile(_ p: Double) -> Double { intervals[min(intervals.count - 1, Int(Double(intervals.count) * p))] }
        let median = percentile(0.5)
        let hitches = intervals.filter { $0 > median * 1.5 }.count
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        let screen = window?.screen?.maximumFramesPerSecond ?? 0
        let occluded = window.map { !$0.occlusionState.contains(.visible) } ?? true
        print(String(format: "PERF view=%@ screen=%dHz%@ fps=%.1f median=%.2fms p95=%.2fms p99=%.2fms max=%.2fms hitches=%d bodies/s=%.1f",
                     "\(visualization)", screen, occluded ? " (occluded)" : "", Double(frames.count) / elapsed, median, percentile(0.95), percentile(0.99),
                     intervals.last ?? 0, hitches, Double(bodies) / elapsed))
        exit(0)
    }
}
#endif
