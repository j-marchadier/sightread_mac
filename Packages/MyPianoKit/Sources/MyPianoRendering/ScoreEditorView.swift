#if canImport(SwiftUI)
import MyPianoCore
import SwiftUI

/// A place on the score under the pointer.
public struct ScorePoint: Sendable, Equatable {
    /// Song time at the pointer, in seconds at 100 % speed.
    public var time: TimeInterval
    public var clef: Clef
    /// Staff position (see ``StaffGeometry``) of the pointer.
    public var step: Int
    /// The note whose head is under the pointer, if any.
    public var noteID: Int?

    public init(time: TimeInterval, clef: Clef, step: Int, noteID: Int? = nil) {
        self.time = time
        self.clef = clef
        self.step = step
        self.noteID = noteID
    }
}

/// Pointer actions on the editable score.
public enum ScorePointerEvent: Sendable {
    /// Button pressed. `extendsSelection` when ⇧ or ⌘ is held.
    case down(ScorePoint, extendsSelection: Bool)
    /// Pointer moved with the button down, from the point where it was pressed.
    case dragged(ScorePoint, from: ScorePoint)
    case up(ScorePoint)
    case doubleClick(ScorePoint)
}

/// The whole score as a page of lines, for editing: notes in `selection` are highlighted, the insertion
/// cursor is drawn at `cursor`, and pointer actions are reported in score terms.
///
/// `version` identifies the scene: change it whenever the scene changes. A line is redrawn only when
/// the version, the width, the appearance, its selected notes or the cursor on it change.
public struct ScoreEditorView: View {
    private let scene: SheetScene
    private let version: Int
    private let selection: Set<Int>
    private let cursor: TimeInterval?
    private let onPointer: @MainActor (ScorePointerEvent) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pressed: ScorePoint?

    public init(scene: SheetScene, version: Int, selection: Set<Int>, cursor: TimeInterval?,
                onPointer: @escaping @MainActor (ScorePointerEvent) -> Void) {
        self.scene = scene
        self.version = version
        self.selection = selection
        self.cursor = cursor
        self.onPointer = onPointer
    }

    public var body: some View {
        GeometryReader { geometry in
            // Lines are laid out for the width; their height does not depend on the view's height.
            let page = PageGeometry(scene: scene, size: CGSize(width: geometry.size.width, height: 0),
                                    palette: SheetPalette.standard(for: colorScheme))
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(page.layout.systems.indices, id: \.self) { index in
                        EditorLineView(page: page, state: lineState(index, page: page))
                            .equatable()
                            .frame(width: page.size.width, height: page.systemHeight)
                    }
                }
                .padding(.vertical, page.topMargin)
                .background(page.renderer.palette.background)
                .contentShape(Rectangle())
                .coordinateSpace(.named(Self.space))
                .gesture(pointerGesture(page))
                .simultaneousGesture(
                    SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space)).onEnded { value in
                        if let point = page.scorePoint(at: value.location) { onPointer(.doubleClick(point)) }
                    }
                )
            }
            .background(page.renderer.palette.background)
            .accessibilityElement()
            .accessibilityLabel(Text("Partition"))
        }
    }

    private static let space = "score-editor"

    private func lineState(_ index: Int, page: PageGeometry) -> EditorLineState {
        let system = page.layout.systems[index]
        let ids = page.systemNotes[index]
        let cursorHere = cursor.flatMap { time in
            time >= system.start && (time < system.end || index == page.layout.systems.count - 1) ? time : nil
        }
        return EditorLineState(version: version, width: page.size.width, isDark: colorScheme == .dark, index: index,
                               selection: Set(ids.filter(selection.contains)), cursor: cursorHere)
    }

    private func pointerGesture(_ page: PageGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let point = page.scorePoint(at: value.location) else { return }
                if let pressed {
                    onPointer(.dragged(point, from: pressed))
                } else {
                    pressed = point
                    let flags = NSEvent.modifierFlags
                    onPointer(.down(point, extendsSelection: flags.contains(.shift) || flags.contains(.command)))
                }
            }
            .onEnded { value in
                if let point = page.scorePoint(at: value.location) { onPointer(.up(point)) }
                pressed = nil
            }
    }
}

/// What an editor line shows; a line is redrawn only when it changes.
struct EditorLineState: Equatable {
    let version: Int
    let width: CGFloat
    let isDark: Bool
    let index: Int
    let selection: Set<Int>
    let cursor: TimeInterval?
}

private struct EditorLineView: View, Equatable {
    let page: PageGeometry
    let state: EditorLineState

    var body: some View {
        Canvas { context, _ in
            var frame = FallingNotesFrame(time: state.cursor ?? -1)
            frame.highlightedNotes = state.selection
            frame.fadesPlayedNotes = false
            page.renderer.drawSystem(page.layout.systems[state.index], isFirst: state.index == 0, in: &context, frame: frame)
        }
    }

    nonisolated static func == (lhs: EditorLineView, rhs: EditorLineView) -> Bool { lhs.state == rhs.state }
}
#endif
