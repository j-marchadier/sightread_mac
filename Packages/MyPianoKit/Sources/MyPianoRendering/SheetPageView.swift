#if canImport(SwiftUI)
import MyPianoCore
import SwiftUI

/// The whole score laid out in lines, like a printed page, with a cursor moving through it.
/// The page scrolls by itself to keep the current line in view.
///
/// Each line is its own view: only the line under the cursor is redrawn every frame, the others only
/// when their notes change colour or the loop moves, and scrolling just moves them.
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
            DisplayTicker {
                PageSystemsView(page: page, frame: frame())
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
    /// Ids of the notes starting in each line, to know when a line's colours change.
    let systemNotes: [[Int]]
    /// Distinguishes this layout from earlier ones (new size, scene or colours).
    let generation: Int

    private static var generations = 0

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
        var notes = [[Int]](repeating: [], count: layout.systems.count)
        if !notes.isEmpty {
            for note in scene.song.notes { notes[layout.systemIndex(at: note.start)].append(note.id) }
        }
        systemNotes = notes
        Self.generations += 1
        generation = Self.generations
    }

    var averageSystemDuration: TimeInterval {
        guard let last = layout.systems.last, !layout.systems.isEmpty else { return 1 }
        return last.end / Double(layout.systems.count)
    }

    private var contentHeight: CGFloat { topMargin * 2 + CGFloat(layout.systems.count) * systemHeight }

    func top(ofSystem index: Int) -> CGFloat { topMargin + CGFloat(index) * systemHeight }

    /// Lines at least partly visible when the page is scrolled by `offset`.
    func visibleSystems(offset: CGFloat) -> Range<Int> {
        guard !layout.systems.isEmpty else { return 0..<0 }
        let first = max(0, Int(floor((offset - topMargin) / systemHeight)))
        let last = min(layout.systems.count - 1, Int(floor((offset + size.height - topMargin) / systemHeight)))
        return first..<max(first, last + 1)
    }

    /// What line `index` shows at the frame `frame`: the line under the cursor follows the frame;
    /// the others only depend on their notes' colours and the loop.
    func lineState(_ index: Int, frame: FallingNotesFrame) -> LineState {
        let system = layout.systems[index]
        let current = layout.systemIndex(at: frame.time)
        if index == current {
            return LineState(generation: generation, index: index, phase: .current, frame: frame)
        }
        let isPast = index < current
        var lineFrame = FallingNotesFrame(time: isPast ? system.end + 1 : system.start - 1, loop: frame.loop)
        if isPast {
            // Only the notes of this line matter: comparing small sets keeps unchanged lines cached.
            let ids = systemNotes[index]
            lineFrame.hitNotes = Set(ids.filter(frame.hitNotes.contains))
            lineFrame.missedNotes = Set(ids.filter(frame.missedNotes.contains))
        }
        return LineState(generation: generation, index: index, phase: isPast ? .past : .future, frame: lineFrame)
    }

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

/// The state a line is drawn from; a line is redrawn only when it changes.
struct LineState: Equatable {
    enum Phase { case past, current, future }

    let generation: Int
    let index: Int
    let phase: Phase
    let frame: FallingNotesFrame

    nonisolated static func == (lhs: LineState, rhs: LineState) -> Bool {
        lhs.generation == rhs.generation && lhs.index == rhs.index && lhs.phase == rhs.phase
            // The line under the cursor changes every frame.
            && lhs.phase != .current
            && lhs.frame.loop == rhs.frame.loop && lhs.frame.hitNotes == rhs.frame.hitNotes
            && lhs.frame.missedNotes == rhs.frame.missedNotes
    }
}

/// The visible lines of the page, scrolled to keep the current one in view.
@MainActor
private struct PageSystemsView: View {
    let page: PageGeometry
    let frame: FallingNotesFrame

    var body: some View {
        let _ = RenderingDiagnostics.onDraw?()
        let offset = page.scrollOffset(at: frame.time)
        ZStack(alignment: .topLeading) {
            page.renderer.palette.background
            ForEach(page.visibleSystems(offset: offset), id: \.self) { index in
                SystemLineView(page: page, state: page.lineState(index, frame: frame))
                    .equatable()
                    .frame(width: page.size.width, height: page.systemHeight)
                    .offset(y: page.top(ofSystem: index) - offset)
            }
        }
        .frame(width: page.size.width, height: page.size.height, alignment: .topLeading)
        .clipped()
    }
}

/// One line of music, redrawn only when its state changes.
private struct SystemLineView: View, Equatable {
    let page: PageGeometry
    let state: LineState

    var body: some View {
        Canvas { context, _ in
            page.renderer.drawSystem(page.layout.systems[state.index], isFirst: state.index == 0, in: &context, frame: state.frame)
        }
    }

    nonisolated static func == (lhs: SystemLineView, rhs: SystemLineView) -> Bool { lhs.state == rhs.state }
}
#endif
