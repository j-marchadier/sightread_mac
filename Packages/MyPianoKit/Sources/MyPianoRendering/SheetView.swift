#if canImport(SwiftUI)
import MyPianoCore
import SwiftUI

/// Static description of a score display; rebuild it when settings change.
public struct SheetScene: Sendable {
    public enum Style: Sendable {
        /// Note heads with a tail showing their length.
        case simplified(SimplifiedScore)
        /// Conventional rhythmic notation.
        case rhythmic(RhythmicScore)
    }

    public var style: Style
    public var song: Song
    public var noteHands: [Hand?]
    public var activeHands: Set<Hand>
    /// Key changes after transposition (or the key forced by the player). Empty when unknown.
    public var keys: [KeySignatureChange]
    /// One colour per note name instead of black heads.
    public var coloredNotes: Bool
    /// Note names written next to the heads, or `nil`.
    public var noteNames: NoteNamingStyle?
    /// Horizontal speed, in points per second of song time.
    public var pointsPerSecond: Double
    /// Finger of each note (index = note id), or `nil` to hide fingers.
    public var fingers: [Finger?]?

    public init(
        style: Style, song: Song, noteHands: [Hand?], activeHands: Set<Hand>, keys: [KeySignatureChange],
        coloredNotes: Bool = false, noteNames: NoteNamingStyle? = nil, pointsPerSecond: Double = 160
    ) {
        self.style = style
        self.song = song
        self.noteHands = noteHands
        self.activeHands = activeHands
        self.keys = keys
        self.coloredNotes = coloredNotes
        self.noteNames = noteNames
        self.pointsPerSecond = pointsPerSecond
    }

    func key(atTick tick: Int) -> KeySignature? {
        (keys.last { $0.tick <= tick } ?? keys.first)?.key
    }
}

/// A grand staff scrolling towards a fixed play line, redrawn at the display's refresh rate.
public struct SheetView: View {
    private let scene: SheetScene
    private let frame: @MainActor () -> FallingNotesFrame
    private let onScrub: (@MainActor (TimeInterval) -> Void)?
    private let onScrubEnded: (@MainActor () -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastDragX: Double?

    public init(
        scene: SheetScene,
        frame: @escaping @MainActor () -> FallingNotesFrame,
        onScrub: (@MainActor (TimeInterval) -> Void)? = nil,
        onScrubEnded: (@MainActor () -> Void)? = nil
    ) {
        self.scene = scene
        self.frame = frame
        self.onScrub = onScrub
        self.onScrubEnded = onScrubEnded
    }

    public var body: some View {
        GeometryReader { geometry in
            let renderer = SheetRenderer(scene: scene, palette: SheetPalette.standard(for: colorScheme), size: geometry.size)
            DisplayTicker {
                let current = frame()
                Canvas { context, _ in
                    renderer.draw(in: &context, frame: current)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let previous = lastDragX ?? value.startLocation.x
                        lastDragX = value.location.x
                        // Dragging the score to the left moves forward in time.
                        onScrub?((previous - value.location.x) / scene.pointsPerSecond)
                    }
                    .onEnded { _ in
                        lastDragX = nil
                        onScrubEnded?()
                    }
            )
            .overlay {
                ScrollWheelReader { delta in
                    onScrub?(delta / scene.pointsPerSecond * 2)
                } onEnded: {
                    onScrubEnded?()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Partition"))
        }
    }
}

struct SheetPalette: Sendable {
    var background: Color
    var ink: Color
    var staffLine: Color
    var faded: Color
    var hit: Color
    var missed: Color
    var playLine: Color
    var loopFill: Color
    var wrong: Color
    var measureNumber: Color
    var leftHand: Color
    var rightHand: Color

    static func standard(for scheme: ColorScheme) -> SheetPalette {
        let dark = scheme == .dark
        return SheetPalette(
            background: dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white,
            ink: dark ? Color(white: 0.92) : Color(white: 0.08),
            staffLine: dark ? Color(white: 0.55) : Color(white: 0.35),
            faded: dark ? Color(white: 0.45) : Color(white: 0.65),
            hit: Color(red: 0.16, green: 0.68, blue: 0.33),
            missed: Color(red: 0.85, green: 0.30, blue: 0.25),
            playLine: Color.accentColor,
            loopFill: Color.accentColor.opacity(0.1),
            wrong: Color(red: 0.92, green: 0.23, blue: 0.23),
            measureNumber: dark ? Color(white: 0.6) : Color(white: 0.45),
            leftHand: Color(red: 0.84, green: 0.42, blue: 0.12),
            rightHand: Color(red: 0.18, green: 0.40, blue: 0.86)
        )
    }

    /// Colours by note name (C … B), for the "coloured notes" option.
    static let stepColors: [Color] = [
        Color(red: 0.93, green: 0.30, blue: 0.40), Color(red: 0.96, green: 0.55, blue: 0.20), Color(red: 0.90, green: 0.75, blue: 0.10),
        Color(red: 0.25, green: 0.70, blue: 0.40), Color(red: 0.20, green: 0.60, blue: 0.90), Color(red: 0.35, green: 0.40, blue: 0.90),
        Color(red: 0.65, green: 0.35, blue: 0.90),
    ]
}

/// Draws one frame of the grand staff. Runs on the main actor, like `Canvas` drawing.
@MainActor
struct SheetRenderer {
    let scene: SheetScene
    let palette: SheetPalette
    let size: CGSize
    let space: CGFloat
    let trebleTop: CGFloat
    let bassTop: CGFloat
    let staffLeft: CGFloat
    let glyphs = GlyphCache.shared

    init(scene: SheetScene, palette: SheetPalette, size: CGSize) {
        self.scene = scene
        self.palette = palette
        self.size = size
        // Two staves, a gap for ledger lines between them and margins above and below.
        space = max(6, min(13, size.height / 26))
        let grandStaffHeight = space * 14
        trebleTop = max(space * 5, (size.height - grandStaffHeight) / 2)
        bassTop = trebleTop + space * 10
        staffLeft = space * 2.2
    }

    /// One line of the full-page score: a grand staff of the given size, `trebleTop` below the line's top.
    init(scene: SheetScene, palette: SheetPalette, size: CGSize, space: CGFloat, trebleTop: CGFloat) {
        self.scene = scene
        self.palette = palette
        self.size = size
        self.space = space
        self.trebleTop = trebleTop
        bassTop = trebleTop + space * 10
        staffLeft = space * 2.2
    }

    // MARK: Geometry

    private func top(_ clef: Clef) -> CGFloat { clef == .treble ? trebleTop : bassTop }

    private func y(_ step: Int, _ clef: Clef) -> CGFloat { top(clef) + CGFloat(step) * space / 2 }

    func headerWidth(key: KeySignature?, time: TimeSignature?) -> CGFloat {
        let accidentals = CGFloat(abs(key?.fifths ?? 0))
        let digits = time.map { CGFloat(max(String($0.numerator).count, String($0.denominator).count)) } ?? 0
        return staffLeft + space * (4.2 + accidentals * 1.05 + 0.6 + digits * 1.9 + 0.8)
    }

    // MARK: Frame

    func draw(in context: inout GraphicsContext, frame: FallingNotesFrame) {
        RenderingDiagnostics.onDraw?()
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
        let tick = scene.song.tempoMap.tick(atSeconds: frame.time)
        let key = scene.key(atTick: tick)
        let time = scene.song.timeSignature(atTick: tick)
        let header = headerWidth(key: key, time: time)
        let playX = header + space * 3
        func x(_ seconds: TimeInterval) -> CGFloat { playX + CGFloat(seconds - frame.time) * scene.pointsPerSecond }
        let visibleFrom = frame.time - Double((playX - header) / scene.pointsPerSecond)
        let visibleTo = frame.time + Double((size.width - playX) / scene.pointsPerSecond)

        drawStaffLines(in: &context, from: 0)
        if let loop = frame.loop {
            let rect = CGRect(x: x(loop.lowerBound), y: trebleTop - space * 2, width: x(loop.upperBound) - x(loop.lowerBound), height: bassTop - trebleTop + space * 8)
            context.fill(Path(rect), with: .color(palette.loopFill))
        }

        var music = context
        music.clip(to: Path(CGRect(x: header, y: 0, width: size.width - header, height: size.height)))
        drawBarLines(in: &music, x: x, from: visibleFrom, to: visibleTo)
        switch scene.style {
        case let .simplified(score): drawSimplified(score, in: &music, frame: frame, x: x, from: visibleFrom, to: visibleTo)
        case let .rhythmic(score): drawRhythmic(score, in: &music, frame: frame, x: x, from: visibleFrom, to: visibleTo)
        }
        // Notes fade out as they pass the play line.
        music.fill(
            Path(CGRect(x: header, y: 0, width: playX - header, height: size.height)),
            with: .linearGradient(Gradient(colors: [palette.background, palette.background.opacity(0)]),
                                  startPoint: CGPoint(x: header, y: 0), endPoint: CGPoint(x: playX - space, y: 0))
        )
        drawPlayLine(in: &context, x: playX)
        drawPressedKeys(in: &context, frame: frame, x: playX)
        drawHeader(in: &context, key: key, time: time)
    }

    // MARK: Full-page score

    /// Draws one line of the full-page score, with the cursor when the line holds the current time.
    /// Key and time signature written at the start of a line (the time only on the first line and where it changes).
    func systemHeader(_ system: PageLayout.System, isFirst: Bool) -> (key: KeySignature?, time: TimeSignature?, width: CGFloat) {
        let startTick = scene.song.tempoMap.tick(atSeconds: system.start)
        let key = scene.key(atTick: startTick)
        let signature = scene.song.timeSignature(atTick: startTick)
        let showsTime = isFirst || system.measures.first.map { index in
            index > 0 && scene.song.timeSignature(atTick: scene.song.measures[index - 1].startTick) != signature
        } == true
        let time = showsTime ? signature : nil
        return (key, time, headerWidth(key: key, time: time))
    }

    func drawSystem(_ system: PageLayout.System, isFirst: Bool, in context: inout GraphicsContext, frame: FallingNotesFrame) {
        let (key, time, header) = systemHeader(system, isFirst: isFirst)
        let right = size.width - space
        let width = right - header - space
        func x(_ seconds: TimeInterval) -> CGFloat { header + space + CGFloat(system.position(of: seconds)) * width }
        let end = x(system.end)

        var lines = Path()
        for top in [trebleTop, bassTop] {
            for line in 0..<5 {
                lines.addRect(CGRect(x: staffLeft, y: top + CGFloat(line) * space - 0.5, width: end - staffLeft, height: 1))
            }
        }
        for index in system.measures.dropFirst() {
            lines.addRect(CGRect(x: x(scene.song.measures[index].start) - 0.6, y: trebleTop, width: 1.2, height: bassTop + space * 4 - trebleTop))
        }
        let isEnd = system.measures.upperBound == scene.song.measures.count
        lines.addRect(CGRect(x: end - (isEnd ? 3.5 : 0.6), y: trebleTop, width: isEnd ? 3.5 : 1.2, height: bassTop + space * 4 - trebleTop))
        if isEnd {
            lines.addRect(CGRect(x: end - 6.5, y: trebleTop, width: 1.2, height: bassTop + space * 4 - trebleTop))
        }
        context.fill(lines, with: .color(palette.staffLine))
        if let first = system.measures.first {
            let number = TextPaths.shared.label(String(scene.song.measures[first].number), size: space * 1.1)
            context.fill(number, at: CGPoint(x: staffLeft, y: trebleTop - space * 2.2), anchor: .bottomLeading, with: palette.measureNumber)
        }

        if let loop = frame.loop, loop.upperBound > system.start, loop.lowerBound < system.end {
            let from = x(max(loop.lowerBound, system.start))
            let to = x(min(loop.upperBound, system.end))
            context.fill(Path(CGRect(x: from, y: trebleTop - space * 2, width: to - from, height: bassTop - trebleTop + space * 8)),
                         with: .color(palette.loopFill))
        }

        var music = context
        music.clip(to: Path(CGRect(x: header, y: 0, width: end - header + space, height: size.height)))
        let to = system.end - 0.0001
        switch scene.style {
        case let .simplified(score): drawSimplified(score, in: &music, frame: frame, x: x, from: system.start, to: to, startingOnly: true)
        case let .rhythmic(score): drawRhythmic(score, in: &music, frame: frame, x: x, from: system.start, to: to, startingOnly: true)
        }
        drawHeader(in: &context, key: key, time: time)

        if frame.time >= system.start && (frame.time < system.end || isEnd) {
            let cursorX = x(frame.time)
            let rect = CGRect(x: cursorX - 1, y: trebleTop - space * 2.5, width: 2.5, height: bassTop + space * 6.5 - trebleTop)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(palette.playLine.opacity(0.85)))
            drawPressedKeys(in: &context, frame: frame, x: cursorX)
        }
    }

    private func drawStaffLines(in context: inout GraphicsContext, from startX: CGFloat) {
        var lines = Path()
        for top in [trebleTop, bassTop] {
            for line in 0..<5 {
                lines.addRect(CGRect(x: startX + staffLeft, y: top + CGFloat(line) * space - 0.5, width: size.width - staffLeft - startX, height: 1))
            }
        }
        context.fill(lines, with: .color(palette.staffLine))
    }

    private func drawBarLines(in context: inout GraphicsContext, x: (TimeInterval) -> CGFloat, from: TimeInterval, to: TimeInterval) {
        var lines = Path()
        for measure in scene.song.measures where measure.start >= from - 1 && measure.start <= to {
            let position = x(measure.start)
            lines.addRect(CGRect(x: position - 0.6, y: trebleTop, width: 1.2, height: bassTop + space * 4 - trebleTop))
            let number = TextPaths.shared.label(String(measure.number), size: space * 1.1)
            context.fill(number, at: CGPoint(x: position + 2, y: trebleTop - space * 0.6), anchor: .bottomLeading, with: palette.measureNumber)
        }
        context.fill(lines, with: .color(palette.staffLine))
    }

    private func drawPlayLine(in context: inout GraphicsContext, x: CGFloat) {
        let rect = CGRect(x: x - 1, y: trebleTop - space * 2.5, width: 2, height: bassTop + space * 6.5 - trebleTop)
        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(palette.playLine.opacity(0.8)))
    }

    /// Brace, clefs, key signature and, when given, time signature.
    private func drawHeader(in context: inout GraphicsContext, key: KeySignature?, time: TimeSignature?) {
        let width = headerWidth(key: key, time: time)
        context.fill(Path(CGRect(x: 0, y: 0, width: width, height: size.height)), with: .color(palette.background))
        var lines = Path()
        for top in [trebleTop, bassTop] {
            for line in 0..<5 {
                lines.addRect(CGRect(x: staffLeft, y: top + CGFloat(line) * space - 0.5, width: width - staffLeft, height: 1))
            }
        }
        lines.addRect(CGRect(x: staffLeft - 0.75, y: trebleTop, width: 1.5, height: bassTop + space * 4 - trebleTop))
        context.fill(lines, with: .color(palette.staffLine))
        let ink = GraphicsContext.Shading.color(palette.ink)

        // Brace spanning both staves.
        if let brace = glyphs.glyph(.brace, staffSpace: space) {
            let height = bassTop + space * 4 - trebleTop
            let scale = height / (space * 4)
            let path = brace.path
                .applying(CGAffineTransform(scaleX: 1, y: scale))
                .applying(CGAffineTransform(translationX: staffLeft - brace.bounds.width - space * 0.4, y: bassTop + space * 4))
            context.fill(path, with: ink)
        }
        let clefX = staffLeft + space * 0.6
        for clef in Clef.allCases {
            if let glyph = glyphs.glyph(clef == .treble ? .gClef : .fClef, staffSpace: space) {
                context.fill(glyph, at: CGPoint(x: clefX, y: y(clef.symbolStep, clef)), with: ink)
            }
        }
        var cursor = clefX + space * 3.4
        if let key, key.fifths != 0, let symbol = glyphs.glyph(key.usesFlats ? .accidentalFlat : .accidentalSharp, staffSpace: space) {
            for clef in Clef.allCases {
                for (i, step) in StaffGeometry.keySignatureSteps(key, clef: clef).enumerated() {
                    context.fill(symbol, at: CGPoint(x: cursor + CGFloat(i) * space * 1.05, y: y(step, clef)), with: ink)
                }
            }
            cursor += CGFloat(abs(key.fifths)) * space * 1.05
        }
        cursor += space * 0.6
        guard let time else { return }
        for clef in Clef.allCases {
            drawNumber(time.numerator, in: &context, x: cursor, baseline: y(2, clef))
            drawNumber(time.denominator, in: &context, x: cursor, baseline: y(6, clef))
        }
    }

    private func drawNumber(_ value: Int, in context: inout GraphicsContext, x: CGFloat, baseline: CGFloat) {
        let digits = String(value).compactMap(\.wholeNumberValue)
        let maxDigits = CGFloat(max(1, digits.count))
        var cursor = x + (maxDigits - CGFloat(digits.count)) * space * 0.95
        for digit in digits {
            guard let glyph = glyphs.glyph(SMuFL.timeSignatureDigit(digit), staffSpace: space) else { continue }
            context.fill(glyph, at: CGPoint(x: cursor, y: baseline), with: .color(palette.ink))
            cursor += glyph.bounds.width + space * 0.1
        }
    }

    // MARK: Colours

    private func noteColor(noteIDs: [Int], pitch: SpelledPitch?, start: TimeInterval, frame: FallingNotesFrame) -> Color {
        if let id = noteIDs.first(where: { frame.missedNotes.contains($0) }), id >= 0 { return palette.missed }
        if !noteIDs.isEmpty, noteIDs.allSatisfy({ frame.hitNotes.contains($0) }) { return palette.hit }
        let hands = noteIDs.compactMap { scene.noteHands.indices.contains($0) ? scene.noteHands[$0] : nil }
        let active = hands.contains { scene.activeHands.contains($0) }
        var base = palette.ink
        if scene.coloredNotes, let pitch { base = SheetPalette.stepColors[pitch.step.rawValue] }
        if !hands.isEmpty && !active { return base.opacity(0.4) }
        return start < frame.time - 0.02 ? base.opacity(0.75) : base
    }

    // MARK: Simplified

    /// `startingOnly` keeps only notes starting in the range (a line of the full-page score).
    private func drawSimplified(_ score: SimplifiedScore, in context: inout GraphicsContext, frame: FallingNotesFrame,
                                x: (TimeInterval) -> CGFloat, from: TimeInterval, to: TimeInterval, startingOnly: Bool = false) {
        guard let head = glyphs.glyph(.noteheadBlack, staffSpace: space) else { return }
        let headWidth = head.bounds.width
        for note in score.heads where (startingOnly ? note.start >= from - 0.0001 : note.end >= from) && note.start <= to {
            let left = x(note.start)
            let color = noteColor(noteIDs: [note.noteID], pitch: note.pitch, start: note.start, frame: frame)
            let baseline = y(note.step, note.clef)
            // Tail showing the length.
            let tail = CGRect(x: left, y: baseline - space * 0.22, width: max(0, x(note.end) - left), height: space * 0.44)
            context.fill(Path(roundedRect: tail, cornerRadius: space * 0.22), with: .color(color.opacity(0.35)))
            drawLedgerLines(for: note.step, clef: note.clef, centerX: left + headWidth / 2, headWidth: headWidth, in: &context)
            context.fill(head, at: CGPoint(x: left, y: baseline), with: .color(color))
            if let accidental = note.accidental { drawAccidental(accidental, rightEdge: left - space * 0.2, baseline: baseline, color: color, in: &context) }
            if let naming = scene.noteNames { drawName(naming.name(of: note.pitch), x: left + headWidth / 2, step: note.step, clef: note.clef, color: color, in: &context) }
        }
        if scene.fingers != nil {
            // Fingers of notes starting together are stacked above (right hand) or below (left hand).
            let visible = score.heads.filter { (startingOnly ? $0.start >= from - 0.0001 : $0.end >= from) && $0.start <= to }
            for group in Dictionary(grouping: visible, by: { "\($0.clef.rawValue)-\(Int(($0.start * 1000).rounded()))" }).values {
                guard let first = group.first else { continue }
                drawFingers(group.map { ($0.noteID, $0.step) }, centerX: x(first.start) + headWidth / 2, clef: first.clef, in: &context)
            }
        }
    }

    // MARK: Rhythmic

    private func drawRhythmic(_ score: RhythmicScore, in context: inout GraphicsContext, frame: FallingNotesFrame,
                              x: (TimeInterval) -> CGFloat, from: TimeInterval, to: TimeInterval, startingOnly: Bool = false) {
        let visible = score.events.filter { (startingOnly ? $0.start >= from - 0.0001 : $0.end >= from - 1) && $0.start <= to }
        var stems: [Int: (x: CGFloat, tip: CGFloat, base: CGFloat, up: Bool)] = [:]

        for event in visible {
            let center = event.isMeasureRest && scene.song.measures.indices.contains(event.measureIndex)
                ? (x(scene.song.measures[event.measureIndex].start) + x(scene.song.measures[event.measureIndex].end)) / 2
                : x(event.start) + space
            let ids = event.heads.compactMap(\.noteID)
            let color = noteColor(noteIDs: ids, pitch: event.heads.first?.pitch, start: event.start, frame: frame)
            if event.isRest {
                drawRest(event, centerX: center, color: color, in: &context)
                continue
            }
            let symbol: SMuFL = event.value <= .whole ? .noteheadWhole : event.value == .half ? .noteheadHalf : .noteheadBlack
            guard let head = glyphs.glyph(symbol, staffSpace: space) else { continue }
            let width = head.bounds.width
            let ordered = event.heads.sorted { $0.step > $1.step } // lowest on the staff first
            var shifted: Set<Int> = []
            for (i, note) in ordered.enumerated() where i > 0 {
                if ordered[i - 1].step - note.step == 1 && !shifted.contains(i - 1) { shifted.insert(i) }
            }
            var accidentalColumn = 0
            var lastAccidentalStep: Int?
            for (i, note) in ordered.enumerated() {
                let offset: CGFloat = shifted.contains(i) ? (event.stemUp ? width : -width) : 0
                let headX = center - width / 2 + offset
                let baseline = y(note.step, event.clef)
                let headColor = scene.coloredNotes ? noteColor(noteIDs: note.noteID.map { [$0] } ?? [], pitch: note.pitch, start: event.start, frame: frame) : color
                drawLedgerLines(for: note.step, clef: event.clef, centerX: headX + width / 2, headWidth: width, in: &context)
                context.fill(head, at: CGPoint(x: headX, y: baseline), with: .color(headColor))
                if let accidental = note.accidental {
                    if let last = lastAccidentalStep, last - note.step < 6 { accidentalColumn += 1 } else { accidentalColumn = 0 }
                    lastAccidentalStep = note.step
                    let right = center - width / 2 - space * 0.25 - CGFloat(accidentalColumn) * space * 1.1
                    drawAccidental(accidental, rightEdge: right, baseline: baseline, color: headColor, in: &context)
                }
                for dot in 0..<event.dots {
                    let dotStep = note.step % 2 == 0 ? note.step - 1 : note.step
                    if let glyph = glyphs.glyph(.augmentationDot, staffSpace: space) {
                        let dotX = center + width / 2 + space * (0.35 + CGFloat(dot) * 0.5) + (shifted.isEmpty ? 0 : width)
                        context.fill(glyph, at: CGPoint(x: dotX, y: y(dotStep, event.clef)), with: .color(headColor))
                    }
                }
                if let naming = scene.noteNames { drawName(naming.name(of: note.pitch), x: headX + width / 2, step: note.step, clef: event.clef, color: headColor, in: &context) }
                if note.tiesToNext {
                    drawTie(from: event, head: note, startX: headX + width, score: score, x: x, in: &context, color: headColor)
                }
            }
            drawFingers(ordered.map { ($0.noteID, $0.step) }, centerX: center, clef: event.clef, in: &context)
            guard event.value > .whole else { continue }
            let lowest = y(ordered.first!.step, event.clef)
            let highest = y(ordered.last!.step, event.clef)
            let middle = y(StaffGeometry.middleLineStep, event.clef)
            let stemX = event.stemUp ? center + width / 2 - 0.6 : center - width / 2 + 0.6
            var tip = event.stemUp ? min(highest - space * 3.5, middle) : max(lowest + space * 3.5, middle)
            if event.value.beamCount > 2 { tip += event.stemUp ? -space * 0.75 : space * 0.75 }
            stems[event.id] = (stemX, tip, event.stemUp ? lowest : highest, event.stemUp)
            if event.beamGroup == nil {
                drawStem(x: stemX, from: event.stemUp ? lowest : highest, to: tip, color: color, in: &context)
                if event.value.beamCount > 0 { drawFlag(event, x: stemX, tip: tip, color: color, in: &context) }
            }
        }
        drawBeams(visible, stems: stems, in: &context, frame: frame)
        drawTupletNumbers(visible, stems: stems, in: &context)
    }

    private func drawStem(x: CGFloat, from: CGFloat, to: CGFloat, color: Color, in context: inout GraphicsContext) {
        let rect = CGRect(x: x - space * 0.06, y: min(from, to), width: space * 0.12, height: abs(to - from))
        context.fill(Path(rect), with: .color(color))
    }

    private func drawFlag(_ event: RhythmicScore.Event, x: CGFloat, tip: CGFloat, color: Color, in context: inout GraphicsContext) {
        let symbol: SMuFL
        switch event.value.beamCount {
        case 1: symbol = event.stemUp ? .flag8thUp : .flag8thDown
        case 2: symbol = event.stemUp ? .flag16thUp : .flag16thDown
        default: symbol = event.stemUp ? .flag32ndUp : .flag32ndDown
        }
        if let glyph = glyphs.glyph(symbol, staffSpace: space) {
            context.fill(glyph, at: CGPoint(x: x - space * 0.06, y: tip), with: .color(color))
        }
    }

    private func drawBeams(_ events: [RhythmicScore.Event], stems: [Int: (x: CGFloat, tip: CGFloat, base: CGFloat, up: Bool)],
                           in context: inout GraphicsContext, frame: FallingNotesFrame) {
        let groups = Dictionary(grouping: events.filter { $0.beamGroup != nil && stems[$0.id] != nil }, by: { $0.beamGroup! })
        for (_, members) in groups {
            let sorted = members.sorted { $0.startTick < $1.startTick }
            guard sorted.count >= 2, let first = stems[sorted.first!.id], let last = stems[sorted.last!.id] else { continue }
            let up = first.up
            // A gently sloped beam that clears every note of the group.
            var slope = (last.tip - first.tip) / max(1, last.x - first.x)
            slope = max(-space / max(1, last.x - first.x), min(space / max(1, last.x - first.x), slope))
            var offset: CGFloat = 0
            for event in sorted {
                guard let stem = stems[event.id] else { continue }
                let lineY = first.tip + slope * (stem.x - first.x)
                offset = up ? min(offset, stem.tip - lineY) : max(offset, stem.tip - lineY)
            }
            func beamY(_ stemX: CGFloat) -> CGFloat { first.tip + offset + slope * (stemX - first.x) }
            let ids = sorted.flatMap { $0.heads.compactMap(\.noteID) }
            let color = noteColor(noteIDs: ids, pitch: nil, start: sorted.first!.start, frame: frame)
            for event in sorted {
                guard let stem = stems[event.id] else { continue }
                drawStem(x: stem.x, from: stem.base, to: beamY(stem.x), color: color, in: &context)
            }
            let thickness = space * 0.5
            let gap = space * 0.25
            let maxLevel = sorted.map(\.value.beamCount).max() ?? 1
            for level in 0..<maxLevel {
                let shift = CGFloat(level) * (thickness + gap) * (up ? 1 : -1)
                var index = 0
                while index < sorted.count {
                    guard sorted[index].value.beamCount > level else { index += 1; continue }
                    var end = index
                    while end + 1 < sorted.count, sorted[end + 1].value.beamCount > level { end += 1 }
                    guard let a = stems[sorted[index].id], let b = stems[sorted[end].id] else { index = end + 1; continue }
                    var startX = a.x - space * 0.06
                    var endX = b.x + space * 0.06
                    if index == end { // a lone shorter note: short hook towards its neighbour
                        if end + 1 < sorted.count { endX = startX + space * 1.1 } else { startX = endX - space * 1.1 }
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: startX, y: beamY(startX) + shift - (up ? 0 : thickness)))
                    path.addLine(to: CGPoint(x: endX, y: beamY(endX) + shift - (up ? 0 : thickness)))
                    path.addLine(to: CGPoint(x: endX, y: beamY(endX) + shift + (up ? thickness : 0)))
                    path.addLine(to: CGPoint(x: startX, y: beamY(startX) + shift + (up ? thickness : 0)))
                    path.closeSubpath()
                    context.fill(path, with: .color(color))
                    index = end + 1
                }
            }
        }
    }

    private func drawTupletNumbers(_ events: [RhythmicScore.Event], stems: [Int: (x: CGFloat, tip: CGFloat, base: CGFloat, up: Bool)],
                                   in context: inout GraphicsContext) {
        guard let three = glyphs.glyph(.tuplet3, staffSpace: space) else { return }
        let ppq = scene.song.ticksPerQuarter
        let groups = Dictionary(grouping: events.filter { $0.tuplet == 3 }, by: { "\($0.clef.rawValue)-\($0.startTick / ppq)" })
        for (_, members) in groups {
            let positions = members.compactMap { stems[$0.id] }
            guard !positions.isEmpty else { continue }
            let up = positions[0].up
            let centerX = (positions.map { $0.x }.min()! + positions.map { $0.x }.max()!) / 2
            let edge = up ? positions.map { $0.tip }.min()! - space * 1.2 : positions.map { $0.tip }.max()! + space * 2
            context.fill(three, centeredAt: centerX, baseline: edge, with: .color(palette.ink))
        }
    }

    private func drawRest(_ event: RhythmicScore.Event, centerX: CGFloat, color: Color, in context: inout GraphicsContext) {
        let symbol: SMuFL
        var step = StaffGeometry.middleLineStep
        if event.isMeasureRest || event.value <= .whole {
            symbol = .restWhole
            step = 2 // hangs from the fourth line
        } else {
            switch event.value {
            case .half: symbol = .restHalf
            case .quarter: symbol = .restQuarter
            case .eighth: symbol = .rest8th
            case .sixteenth: symbol = .rest16th
            default: symbol = .rest32nd
            }
        }
        guard let glyph = glyphs.glyph(symbol, staffSpace: space) else { return }
        context.fill(glyph, centeredAt: centerX, baseline: y(step, event.clef), with: .color(color.opacity(0.85)))
        for dot in 0..<event.dots {
            if let dotGlyph = glyphs.glyph(.augmentationDot, staffSpace: space) {
                context.fill(dotGlyph, at: CGPoint(x: centerX + glyph.bounds.width / 2 + space * (0.3 + CGFloat(dot) * 0.5), y: y(3, event.clef)), with: .color(color))
            }
        }
    }

    private func drawTie(from event: RhythmicScore.Event, head: RhythmicScore.Head, startX: CGFloat, score: RhythmicScore,
                         x: (TimeInterval) -> CGFloat, in context: inout GraphicsContext, color: Color) {
        guard let next = score.events.first(where: {
            $0.clef == event.clef && $0.startTick >= event.startTick + event.durationTicks
                && $0.heads.contains { $0.pitch == head.pitch }
        }) else { return }
        let endX = x(next.start) + space * 0.4
        let baseline = y(head.step, event.clef)
        let direction: CGFloat = event.stemUp ? 1 : -1
        let startY = baseline + direction * space * 0.6
        let height = min(space * 1.2, max(space * 0.5, (endX - startX) * 0.12)) * direction
        var path = Path()
        path.move(to: CGPoint(x: startX + space * 0.2, y: startY))
        path.addQuadCurve(to: CGPoint(x: endX, y: startY), control: CGPoint(x: (startX + endX) / 2, y: startY + height))
        path.addQuadCurve(to: CGPoint(x: startX + space * 0.2, y: startY), control: CGPoint(x: (startX + endX) / 2, y: startY + height * 0.7))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    // MARK: Shared pieces

    /// Finger numbers of notes sounding together, stacked above the staff for the right hand and
    /// below it for the left hand. Suggested fingers are lighter and in italics.
    private func drawFingers(_ heads: [(noteID: Int?, step: Int)], centerX: CGFloat, clef: Clef, in context: inout GraphicsContext) {
        guard let fingers = scene.fingers else { return }
        let numbered = heads.compactMap { head -> (step: Int, finger: Finger, hand: Hand?)? in
            guard let id = head.noteID, fingers.indices.contains(id), let finger = fingers[id] else { return nil }
            return (head.step, finger, scene.noteHands.indices.contains(id) ? scene.noteHands[id] : nil)
        }
        guard !numbered.isEmpty else { return }
        let above = (numbered.first?.hand).map { $0 == .right } ?? (clef == .treble)
        let extra: CGFloat = scene.noteNames == nil ? 0 : space * 1.3
        let lineHeight = space * 1.15
        let ordered = numbered.sorted { above ? $0.step > $1.step : $0.step < $1.step } // nearest the staff first
        var edge: CGFloat
        if above {
            edge = min(y(numbered.map(\.step).min()!, clef), top(clef)) - space * 0.9 - extra
        } else {
            edge = max(y(numbered.map(\.step).max()!, clef), top(clef) + space * 4) + space * 0.9 + extra
        }
        for item in ordered {
            let written = item.finger.isWritten
            let label = TextPaths.shared.label(String(item.finger.number), size: space * 1.05,
                                               weight: written ? .semibold : .regular, italic: !written)
            context.fill(label, at: CGPoint(x: centerX, y: edge), anchor: above ? .bottom : .top,
                         with: written ? palette.ink : palette.faded)
            edge += above ? -lineHeight : lineHeight
        }
    }

    private func drawLedgerLines(for step: Int, clef: Clef, centerX: CGFloat, headWidth: CGFloat, in context: inout GraphicsContext) {
        let ledgers = StaffGeometry.ledgerLineSteps(for: step)
        guard !ledgers.isEmpty else { return }
        var path = Path()
        for ledger in ledgers {
            path.addRect(CGRect(x: centerX - headWidth * 0.8, y: y(ledger, clef) - 0.6, width: headWidth * 1.6, height: 1.2))
        }
        context.fill(path, with: .color(palette.staffLine))
    }

    private func drawAccidental(_ accidental: Accidental, rightEdge: CGFloat, baseline: CGFloat, color: Color, in context: inout GraphicsContext) {
        let symbol: SMuFL
        switch accidental {
        case .flat: symbol = .accidentalFlat
        case .natural: symbol = .accidentalNatural
        case .sharp: symbol = .accidentalSharp
        case .doubleSharp: symbol = .accidentalDoubleSharp
        case .doubleFlat: symbol = .accidentalDoubleFlat
        }
        guard let glyph = glyphs.glyph(symbol, staffSpace: space) else { return }
        context.fill(glyph, at: CGPoint(x: rightEdge - glyph.bounds.maxX, y: baseline), with: .color(color))
    }

    private func drawName(_ name: String, x: CGFloat, step: Int, clef: Clef, color: Color, in context: inout GraphicsContext) {
        let below = step < StaffGeometry.middleLineStep
        let label = TextPaths.shared.label(name, size: space * 0.95, weight: .medium)
        let anchorY = y(step, clef) + (below ? space * 1.1 : -space * 1.1)
        context.fill(label, at: CGPoint(x: x, y: anchorY), anchor: below ? .top : .bottom, with: color)
    }

    private func drawPressedKeys(in context: inout GraphicsContext, frame: FallingNotesFrame, x: CGFloat) {
        guard !frame.pressedKeys.isEmpty, let head = glyphs.glyph(.noteheadBlack, staffSpace: space) else { return }
        let tick = scene.song.tempoMap.tick(atSeconds: frame.time)
        let key = scene.key(atTick: tick)
        let expected = Set(scene.song.notes.filter { note in
            note.start <= frame.time + 0.05 && note.end > frame.time
                && (scene.noteHands.indices.contains(note.id) ? scene.noteHands[note.id] : nil).map { scene.activeHands.contains($0) } == true
        }.map(\.pitch))
        for pitch in frame.pressedKeys {
            let spelled = Speller.spell(Int(pitch), in: key)
            let clef = Clef.forNote(hand: nil, pitch: Int(pitch))
            let step = StaffGeometry.step(of: spelled, clef: clef)
            let color = expected.contains(pitch) ? palette.hit : palette.wrong
            drawLedgerLines(for: step, clef: clef, centerX: x, headWidth: head.bounds.width, in: &context)
            context.fill(head, centeredAt: x, baseline: y(step, clef), with: .color(color.opacity(0.85)))
            if let accidental = Speller.accidentalAgainstKey(spelled, key: key) {
                drawAccidental(accidental, rightEdge: x - head.bounds.width / 2 - space * 0.2, baseline: y(step, clef), color: color, in: &context)
            }
        }
    }
}
#endif
