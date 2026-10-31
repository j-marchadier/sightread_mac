import PianissimacCore
import PianissimacRendering
import SwiftUI

/// The song as a strip of measures: click or drag to move, drag the handles to change the loop.
struct MeasureTimelineView: View {
    let player: PlayerViewModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = max(player.song.duration, 0.001)
            let x = { (time: TimeInterval) in CGFloat(time / duration) * width }
            ZStack(alignment: .topLeading) {
                // Transparent: the timeline sits on the control bar's glass.
                Color.clear
                if let range = player.settings.loop?.timeRange(in: player.song) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: max(2, x(range.upperBound) - x(range.lowerBound)))
                        .offset(x: x(range.lowerBound))
                    loopHandle(at: x(range.lowerBound), width: width, isStart: true)
                    loopHandle(at: x(range.upperBound), width: width, isStart: false)
                }
                Canvas { context, size in
                    for measure in player.song.measures {
                        let mx = x(measure.start)
                        let major = (measure.number - 1) % 4 == 0
                        context.fill(Path(CGRect(x: mx, y: major ? 0 : size.height * 0.55, width: 1, height: size.height)),
                                     with: .color(.secondary.opacity(major ? 0.5 : 0.25)))
                        if major && size.width / CGFloat(max(1, player.song.measures.count)) * 4 > 22 {
                            context.draw(Text("\(measure.number)").font(.caption2).foregroundStyle(.secondary),
                                         at: CGPoint(x: mx + 3, y: 2), anchor: .topLeading)
                        }
                    }
                }
                DisplayTicker {
                    let time = player.engine.snapshot().time
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: min(width - 2, max(0, x(time) - 1)))
                }
            }
            .coordinateSpace(.named("timeline"))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                player.seek(to: TimeInterval(max(0, min(1, value.location.x / max(1, width)))) * duration)
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Position dans le morceau"))
        .accessibilityValue(Text("Mesure \(player.currentMeasureNumber) sur \(player.song.measures.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.nextMeasure()
            case .decrement: player.previousMeasure()
            @unknown default: break
            }
        }
    }

    private func loopHandle(at position: CGFloat, width: CGFloat, isStart: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 6)
            .padding(.vertical, 3)
            .offset(x: position - 3)
            .gesture(DragGesture(coordinateSpace: .named("timeline")).onChanged { value in
                moveLoop(isStart: isStart, to: value.location.x / max(1, width))
            })
            .help(isStart ? LocalizedStringKey("Début de la boucle") : "Fin de la boucle")
    }

    private func moveLoop(isStart: Bool, to fraction: CGFloat) {
        let time = TimeInterval(max(0, min(1, fraction))) * player.song.duration
        guard let index = player.song.measures.lastIndex(where: { $0.start <= time }) else { return }
        player.update { settings in
            guard var loop = settings.loop else { return }
            if isStart { loop.firstMeasure = min(index, loop.lastMeasure) } else { loop.lastMeasure = max(index, loop.firstMeasure) }
            settings.loop = loop
        }
    }
}
