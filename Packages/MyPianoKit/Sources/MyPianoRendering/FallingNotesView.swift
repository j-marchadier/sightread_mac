#if canImport(SwiftUI)
import MyPianoCore
import SwiftUI

/// Static description of what the falling-notes view shows; rebuild it when settings change.
public struct FallingNotesScene: Sendable {
    public var song: Song
    /// Hand of each note (index = note id); `nil` for accompaniment.
    public var noteHands: [Hand?]
    public var activeHands: Set<Hand>
    /// Name drawn on each note, or `nil` to hide names.
    public var labels: [String]?
    /// Naming used for the C keys of the keyboard, or `nil` to hide them.
    public var keyNames: NoteNamingStyle?
    public var transpose: Int
    public var keyboardRange: ClosedRange<UInt8>
    /// Falling speed, in points per second of song time.
    public var pointsPerSecond: Double
    let longestNote: TimeInterval

    public init(
        song: Song, noteHands: [Hand?], activeHands: Set<Hand>, labels: [String]?, keyNames: NoteNamingStyle?,
        transpose: Int, keyboardRange: ClosedRange<UInt8>, pointsPerSecond: Double = 220
    ) {
        self.song = song
        self.noteHands = noteHands
        self.activeHands = activeHands
        self.labels = labels
        self.keyNames = keyNames
        self.transpose = transpose
        self.keyboardRange = keyboardRange
        self.pointsPerSecond = pointsPerSecond
        longestNote = song.longestNoteDuration
    }
}

/// Live state for one frame.
public struct FallingNotesFrame: Sendable {
    public var time: TimeInterval
    public var hitNotes: Set<Int>
    public var missedNotes: Set<Int>
    public var pressedKeys: Set<UInt8>
    public var loop: ClosedRange<TimeInterval>?
    /// Free play: notes played live, drawn rising from the keyboard (times in host seconds).
    public var liveNotes: [LiveNote]
    /// Host time of the frame, for `liveNotes`.
    public var hostTime: TimeInterval

    public init(
        time: TimeInterval, hitNotes: Set<Int> = [], missedNotes: Set<Int> = [], pressedKeys: Set<UInt8> = [],
        loop: ClosedRange<TimeInterval>? = nil, liveNotes: [LiveNote] = [], hostTime: TimeInterval = 0
    ) {
        self.time = time
        self.hitNotes = hitNotes
        self.missedNotes = missedNotes
        self.pressedKeys = pressedKeys
        self.loop = loop
        self.liveNotes = liveNotes
        self.hostTime = hostTime
    }
}

/// Notes falling onto a piano keyboard, redrawn at the display's refresh rate.
///
/// Clicking or dragging on the keyboard plays notes; dragging or scrolling above it moves
/// through the song.
public struct FallingNotesView: View {
    private let scene: FallingNotesScene
    private let frame: @MainActor () -> FallingNotesFrame
    private let onKey: (@MainActor (UInt8, Bool) -> Void)?
    private let onScrub: (@MainActor (TimeInterval) -> Void)?
    private let onScrubEnded: (@MainActor () -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var mouseKey: UInt8?
    @State private var dragMode: DragMode?
    @State private var lastDragY: Double = 0

    private enum DragMode { case keyboard, scrub }

    /// - Parameters:
    ///   - onKey: Called with `(pitch, isDown)` when the mouse plays a key.
    ///   - onScrub: Called with a song-time offset while dragging or scrolling above the keyboard.
    public init(
        scene: FallingNotesScene,
        frame: @escaping @MainActor () -> FallingNotesFrame,
        onKey: (@MainActor (UInt8, Bool) -> Void)? = nil,
        onScrub: (@MainActor (TimeInterval) -> Void)? = nil,
        onScrubEnded: (@MainActor () -> Void)? = nil
    ) {
        self.scene = scene
        self.frame = frame
        self.onKey = onKey
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
    }

    public var body: some View {
        GeometryReader { geometry in
            let renderer = FallingNotesRenderer(scene: scene, palette: .standard(for: colorScheme), size: geometry.size)
            TimelineView(.animation) { _ in
                let current = frame()
                Canvas { context, _ in
                    renderer.draw(in: &context, frame: current)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(renderer))
            .overlay {
                ScrollWheelReader { deltaY in
                    // Same direction as dragging: moving the content down goes forward in time.
                    onScrub?(deltaY / scene.pointsPerSecond * 2)
                } onEnded: {
                    onScrubEnded?()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Notes qui tombent"))
        }
    }

    private func dragGesture(_ renderer: FallingNotesRenderer) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = value.startLocation.y >= renderer.hitLineY ? .keyboard : .scrub
                    lastDragY = value.startLocation.y
                }
                switch dragMode {
                case .keyboard:
                    let key = renderer.keyboard.key(
                        atX: value.location.x, y: value.location.y - renderer.keyboardTop,
                        whiteKeyHeight: renderer.whiteKeyHeight
                    )
                    if key != mouseKey {
                        if let old = mouseKey { onKey?(old, false) }
                        if let key { onKey?(key, true) }
                        mouseKey = key
                    }
                case .scrub:
                    let delta = value.location.y - lastDragY
                    lastDragY = value.location.y
                    onScrub?(delta / scene.pointsPerSecond)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if let old = mouseKey { onKey?(old, false) }
                mouseKey = nil
                if dragMode == .scrub { onScrubEnded?() }
                dragMode = nil
            }
    }
}

/// Draws one frame. Runs on the main actor, like `Canvas` drawing (text views are main-actor bound).
@MainActor
struct FallingNotesRenderer {
    let scene: FallingNotesScene
    let palette: PianoPalette
    let size: CGSize
    let keyboard: KeyboardLayout
    let whiteKeyHeight: Double
    let keyboardTop: Double
    let hitLineY: Double
    let layout: FallingNotesLayout

    init(scene: FallingNotesScene, palette: PianoPalette, size: CGSize) {
        self.scene = scene
        self.palette = palette
        self.size = size
        keyboard = KeyboardLayout(range: scene.keyboardRange, width: size.width)
        whiteKeyHeight = keyboard.whiteKeyHeight(maximum: max(48, min(180, size.height * 0.24)))
        keyboardTop = size.height - whiteKeyHeight
        hitLineY = keyboardTop - 3
        layout = FallingNotesLayout(keyboard: keyboard, hitLineY: hitLineY, pointsPerSecond: scene.pointsPerSecond, transpose: scene.transpose)
    }

    func draw(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        let visible = layout.visibleNoteIndices(in: scene.song, now: frame.time, maxNoteDuration: scene.longestNote)
        var notesArea = context
        notesArea.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: hitLineY)))
        drawLanes(in: &notesArea)
        drawLoop(in: &notesArea, frame: frame)
        drawMeasures(in: &notesArea, frame: frame)
        drawNotes(in: &notesArea, frame: frame, indices: visible)
        drawLiveNotes(in: &notesArea, frame: frame)
        drawHitLine(in: &context)
        drawKeyboard(in: &context, frame: frame, indices: visible)
    }

    private func drawLanes(in context: inout GraphicsContext) {
        var path = Path()
        for key in keyboard.keys where !key.isBlack && key.pitch % 12 == 0 {
            path.addRect(CGRect(x: key.x, y: 0, width: 1, height: hitLineY))
        }
        context.fill(path, with: .color(palette.octaveLine))
    }

    private func drawLoop(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        guard let loop = frame.loop else { return }
        let top = layout.y(for: loop.upperBound, now: frame.time)
        let bottom = layout.y(for: loop.lowerBound, now: frame.time)
        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)), with: .color(palette.loopFill))
        var edges = Path()
        edges.addRect(CGRect(x: 0, y: top - 1, width: size.width, height: 2))
        edges.addRect(CGRect(x: 0, y: bottom - 1, width: size.width, height: 2))
        context.fill(edges, with: .color(palette.hitLine.opacity(0.6)))
    }

    private func drawMeasures(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        let indices = layout.visibleMeasureIndices(in: scene.song, now: frame.time)
        var lines = Path()
        for index in indices {
            let y = layout.y(for: scene.song.measures[index].start, now: frame.time)
            lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            let number = Text(verbatim: String(scene.song.measures[index].number)).font(.caption2.monospacedDigit()).foregroundStyle(palette.measureText)
            context.draw(number, at: CGPoint(x: 6, y: y - 3), anchor: .bottomLeading)
        }
        context.fill(lines, with: .color(palette.measureLine))
    }

    private func drawNotes(in context: inout GraphicsContext, frame: FallingNotesFrame, indices: Range<Int>) {
        for index in indices {
            let note = scene.song.notes[index]
            guard let rect = layout.rect(for: note, now: frame.time), rect.y < hitLineY, rect.y + rect.height > 0 else { continue }
            let hand = scene.noteHands.indices.contains(note.id) ? scene.noteHands[note.id] : nil
            let isActive = hand.map { scene.activeHands.contains($0) } ?? false
            let onBlack = PianoKeys.isBlack(PianoKeys.transpose(note.pitch, by: scene.transpose))
            var color = palette.color(for: hand, onBlackKey: onBlack)
            if frame.missedNotes.contains(note.id) {
                color = palette.missed
            } else if hand != nil && !isActive {
                color = color.opacity(0.35)
            }
            let shape = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let radius = min(5, rect.width / 3, rect.height / 2)
            let path = Path(roundedRect: shape, cornerRadius: radius)
            context.fill(path, with: .color(color))
            if frame.hitNotes.contains(note.id) {
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
            if let labels = scene.labels, labels.indices.contains(note.id), rect.width >= 9, rect.height >= 14 {
                let fontSize = min(12, max(7, rect.width * 0.5))
                let label = Text(verbatim: labels[note.id]).font(.system(size: fontSize, weight: .semibold)).foregroundStyle(palette.noteText)
                context.draw(label, at: CGPoint(x: shape.midX, y: shape.maxY - 3), anchor: .bottom)
            }
        }
    }

    /// Notes played live rise from the keyboard and keep growing while held.
    private func drawLiveNotes(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        for note in frame.liveNotes {
            guard let key = keyboard.key(for: note.pitch) else { continue }
            let end = note.end ?? frame.hostTime
            let bottom = hitLineY - CGFloat(frame.hostTime - end) * scene.pointsPerSecond
            let height = max(4, CGFloat(end - note.start) * scene.pointsPerSecond)
            guard bottom > 0 else { continue }
            let inset = key.isBlack ? 0.5 : max(1, key.width * 0.08)
            let rect = CGRect(x: key.x + inset, y: bottom - height, width: max(1, key.width - 2 * inset), height: height)
            let path = Path(roundedRect: rect, cornerRadius: min(5, rect.width / 3, rect.height / 2))
            context.fill(path, with: .color(palette.color(for: .right, onBlackKey: key.isBlack)))
        }
    }

    private func drawHitLine(in context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: hitLineY, width: size.width, height: 3)), with: .color(palette.hitLine))
    }

    private func drawKeyboard(in context: inout GraphicsContext, frame: FallingNotesFrame, indices: Range<Int>) {
        // Song notes sounding now light their keys in the hand's colour.
        var sounding: [UInt8: Hand?] = [:]
        for index in indices {
            let note = scene.song.notes[index]
            guard note.start <= frame.time, frame.time < note.end else { continue }
            let pitch = PianoKeys.transpose(note.pitch, by: scene.transpose)
            let hand = scene.noteHands.indices.contains(note.id) ? scene.noteHands[note.id] : nil
            if sounding[pitch] == nil || hand != nil { sounding[pitch] = hand }
        }
        let expected = Set(sounding.filter { $0.value != nil }.map(\.key))

        func fill(for key: KeyboardLayout.Key) -> Color? {
            if frame.pressedKeys.contains(key.pitch) {
                if let hand = sounding[key.pitch] { return palette.color(for: hand, onBlackKey: key.isBlack) }
                // Red only when another note of a practised hand is expected right now.
                return expected.isEmpty ? palette.pressedKey : palette.wrongKey
            }
            if let hand = sounding[key.pitch] {
                return palette.color(for: hand, onBlackKey: key.isBlack).opacity(0.55)
            }
            return nil
        }

        let blackHeight = whiteKeyHeight * KeyboardLayout.blackKeyHeightRatio
        context.fill(Path(CGRect(x: 0, y: keyboardTop, width: size.width, height: whiteKeyHeight)), with: .color(palette.whiteKeyBorder))
        for key in keyboard.keys where !key.isBlack {
            let rect = CGRect(x: key.x + 0.5, y: keyboardTop, width: key.width - 1, height: whiteKeyHeight - 1)
            let path = Path(roundedRect: rect, cornerSize: CGSize(width: 3, height: 3))
            context.fill(path, with: .color(palette.whiteKey))
            if let color = fill(for: key) { context.fill(path, with: .color(color)) }
            if let style = scene.keyNames, key.pitch % 12 == 0, key.width >= 11 {
                let name = style.name(of: Speller.spell(Int(key.pitch), in: nil), includeOctave: true)
                let label = Text(verbatim: name).font(.system(size: min(11, key.width * 0.45))).foregroundStyle(palette.keyLabel)
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - 4), anchor: .bottom)
            }
        }
        for key in keyboard.keys where key.isBlack {
            let rect = CGRect(x: key.x, y: keyboardTop, width: key.width, height: blackHeight)
            let path = Path(roundedRect: rect, cornerSize: CGSize(width: 2, height: 2))
            context.fill(path, with: .linearGradient(
                Gradient(colors: [palette.blackKey, palette.blackKey.opacity(0.85)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
            if let color = fill(for: key) { context.fill(path, with: .color(color)) }
        }
    }
}
#endif
