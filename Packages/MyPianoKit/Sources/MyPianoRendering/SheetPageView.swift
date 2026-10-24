#if canImport(SwiftUI)
import MyPianoCore
import SwiftUI

/// The whole score laid out in lines, like a printed page, with a cursor moving through it.
/// The page scrolls by itself to keep the current line in view.
public struct SheetPageView: View {
    private let scene: SheetScene
    private let frame: @MainActor () -> FallingNotesFrame
    private let onSeek: (@MainActor (TimeInterval) -> Void)?
    private let onScrub: (@MainActor (TimeInterval) -> Void)?
    private let onScrubEnded: (@MainActor () -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        scene: SheetScene,
        frame: @escaping @MainActor () -> FallingNotesFrame,
        onSeek: (@MainActor (TimeInterval) -> Void)? = nil,
        onScrub: (@MainActor (TimeInterval) -> Void)? = nil,
        onScrubEnded: (@MainActor () -> Void)? = nil
    ) {
        self.scene = scene
        self.frame = frame
        self.onSeek = onSeek
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
    }

    public var body: some View {
        GeometryReader { geometry in
            let page = PageGeometry(scene: scene, size: geometry.size, palette: SheetPalette.standard(for: colorScheme))
            TimelineView(.animation) { _ in
                let current = frame()
                Canvas { context, _ in
                    page.draw(in: &context, frame: current)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let time = page.time(at: location, currentTime: frame().time) { onSeek?(time) }
            }
            .overlay {
                ScrollWheelReader { delta in
                    onScrub?(delta / page.systemHeight * page.averageSystemDuration)
                } onEnded: {
                    onScrubEnded?()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Partition"))
        }
    }
}

/// Lines of the page and how far the page is scrolled at a given time.
@MainActor
struct PageGeometry {
    let renderer: SheetRenderer
    let layout: PageLayout
    let size: CGSize
    let space: CGFloat
    let systemHeight: CGFloat
    let topMargin: CGFloat

    /// `staffSpace` defaults to a size readable on screen for the given width.
    init(scene: SheetScene, size: CGSize, palette: SheetPalette, staffSpace: CGFloat? = nil) {
        self.size = size
        space = staffSpace ?? max(7, min(12, size.width / 110))
        systemHeight = space * 23
        topMargin = space
        renderer = SheetRenderer(scene: scene, palette: palette, size: CGSize(width: size.width, height: systemHeight),
                                 space: space, trebleTop: space * 5.5)
        // Room for the widest header (clefs, the most accidentals, a time signature), then margins.
        let widestKey = scene.keys.max { abs($0.key.fifths) < abs($1.key.fifths) }?.key
        let header = renderer.headerWidth(key: widestKey, time: scene.song.primaryTimeSignature)
        layout = PageLayout(measures: scene.song.measures, width: Double(size.width - header - space * 3),
                            pointsPerSecond: scene.pointsPerSecond * 0.75, minimumMeasureWidth: Double(space * 9))
    }

    var averageSystemDuration: TimeInterval {
        guard let last = layout.systems.last, !layout.systems.isEmpty else { return 1 }
        return last.end / Double(layout.systems.count)
    }

    private var contentHeight: CGFloat { topMargin * 2 + CGFloat(layout.systems.count) * systemHeight }

    private func top(ofSystem index: Int) -> CGFloat { topMargin + CGFloat(index) * systemHeight }

    /// Scroll offset keeping the current line about a fifth down the view. Near the end of a line
    /// the page glides to the next one, so the eye can read ahead.
    func scrollOffset(at time: TimeInterval) -> CGFloat {
        guard !layout.systems.isEmpty else { return 0 }
        let maximum = max(0, contentHeight - size.height)
        func target(_ index: Int) -> CGFloat { min(maximum, max(0, top(ofSystem: index) - size.height * 0.2)) }
        let index = layout.systemIndex(at: time)
        let system = layout.systems[index]
        guard index + 1 < layout.systems.count, system.end > system.start else { return target(index) }
        let progress = (time - system.start) / (system.end - system.start)
        let glide = min(1, max(0, (progress - 0.75) / 0.25))
        let eased = glide * glide * (3 - 2 * glide)
        return target(index) + (target(index + 1) - target(index)) * CGFloat(eased)
    }

    func draw(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        RenderingDiagnostics.onDraw?()
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(renderer.palette.background))
        let offset = scrollOffset(at: frame.time)
        for (index, system) in layout.systems.enumerated() {
            let y = top(ofSystem: index) - offset
            guard y + systemHeight > 0, y < size.height else { continue }
            var line = context
            line.translateBy(x: 0, y: y)
            renderer.drawSystem(system, isFirst: index == 0, in: &line, frame: frame)
        }
    }

    /// The song time under a point of the view, if it falls on a line's music.
    func time(at point: CGPoint, currentTime: TimeInterval) -> TimeInterval? {
        let y = point.y + scrollOffset(at: currentTime) - topMargin
        let index = Int(floor(y / systemHeight))
        guard layout.systems.indices.contains(index) else { return nil }
        let system = layout.systems[index]
        let header = renderer.systemHeader(system, isFirst: index == 0).width
        let width = size.width - space - header - space
        guard width > 0, point.x >= header else { return nil }
        return system.time(at: Double((point.x - header - space) / width))
    }
}
#endif
