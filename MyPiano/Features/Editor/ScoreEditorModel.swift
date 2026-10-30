import Foundation
import MyPianoCore
import MyPianoRendering
import Observation

/// One open score editor: the song's notes being edited, the selection, the insertion cursor and the
/// note value used to insert. Every change is undoable and saved automatically beside the library.
@MainActor
@Observable
final class ScoreEditorModel {
    /// A note with a tag that stays the same while it is moved or changed (note ids change on every edit).
    struct TaggedNote: Equatable {
        let tag: Int
        var note: EditedNote
    }

    let songID: String
    let title: String
    private(set) var song: Song
    private(set) var scene: SheetScene
    /// Changes whenever `scene` changes, so the score view knows which lines to redraw.
    private(set) var version = 0
    private(set) var notes: [TaggedNote] = []
    /// Tags of the selected notes.
    private(set) var selection: Set<Int> = []
    /// Where notes are inserted, in ticks.
    private(set) var cursorTick: Int?
    /// Clicks and MIDI keys insert notes (otherwise clicks select).
    var isInserting = false {
        didSet { if isInserting && cursorTick == nil { cursorTick = selectionStart ?? 0 } }
    }
    var noteValue: NoteValue = .quarter
    var isDotted = false
    /// The notes differ from the song's file.
    private(set) var isEdited: Bool
    var saveError: String?

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private let original: Song
    @ObservationIgnored private let settings: PracticeSettings
    @ObservationIgnored private let display: DisplayOptions
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let playNote: (UInt8) -> Void
    @ObservationIgnored private var nextTag = 0
    @ObservationIgnored private var idByTag: [Int: Int] = [:]
    @ObservationIgnored private var tagByID: [Int] = []
    @ObservationIgnored private var dragOrigin: (notes: [TaggedNote], dSteps: Int, dTicks: Int)?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var chord: (tick: Int, time: Date)?
    @ObservationIgnored private var lastPitch: UInt8 = 72

    init(songID: String, library: LibraryModel, playNote: @escaping (UInt8) -> Void) throws {
        guard let entry = library.database.song(songID) else { throw CocoaError(.fileNoSuchFile) }
        self.songID = songID
        self.library = library
        self.playNote = playNote
        title = entry.title
        original = try library.originalSong(for: songID)
        let current = try library.song(for: songID)
        settings = entry.settings ?? Preferences.newSongSettings(handAssignment: HandAssigner.assign(current))
        var display = Preferences.display
        display.fingering = .written
        self.display = display
        song = current
        scene = SheetScene(style: .simplified(SimplifiedScore(song: current, hands: [], transpose: 0)), song: current,
                           noteHands: [], activeHands: [.left, .right], keys: [])
        isEdited = library.hasEdits(songID)
        notes = current.editedNotes.map { note in
            defer { nextTag += 1 }
            return TaggedNote(tag: nextTag, note: note)
        }
        rebuild(save: false)
    }

    // MARK: Score

    var ticksPerQuarter: Int { song.ticksPerQuarter }

    /// Ids, in `song`, of the selected notes.
    var selectedNoteIDs: Set<Int> { Set(selection.compactMap { idByTag[$0] }) }

    var cursorTime: TimeInterval? { cursorTick.map { song.tempoMap.seconds(atTick: $0) } }

    var selectedNotes: [EditedNote] { notes.filter { selection.contains($0.tag) }.map(\.note) }

    private var selectionStart: Int? { selectedNotes.map(\.startTick).min() }

    /// Hands can be given per note only when each hand has its own track.
    var canChangeHand: Bool {
        !settings.handAssignment.leftTracks.isEmpty && !settings.handAssignment.rightTracks.isEmpty
    }

    func hand(of note: EditedNote) -> Hand? {
        let assignment = settings.handAssignment
        if let split = assignment.splitTracks[note.track] { return note.pitch >= split ? .right : .left }
        if assignment.rightTracks.contains(note.track) { return .right }
        if assignment.leftTracks.contains(note.track) { return .left }
        return nil
    }

    private func track(for hand: Hand) -> Int {
        let assignment = settings.handAssignment
        let tracks = hand == .right ? assignment.rightTracks : assignment.leftTracks
        return tracks.min() ?? assignment.splitTracks.keys.min() ?? assignment.rightTracks.union(assignment.leftTracks).min() ?? 0
    }

    private var valueTicks: Int { noteValue.ticks(ticksPerQuarter: ticksPerQuarter, dots: isDotted ? 1 : 0) }

    /// The start of the note value's slot containing `tick`, counted from the start of its measure.
    private func snap(_ tick: Int) -> Int {
        let grid = max(1, noteValue.ticks(ticksPerQuarter: ticksPerQuarter))
        guard !song.measures.isEmpty else { return max(0, tick / grid * grid) }
        let measure = song.measures[song.measureIndex(atTick: max(0, tick))]
        let offset = max(0, tick - measure.startTick)
        return measure.startTick + offset / grid * grid
    }

    private func tick(at time: TimeInterval) -> Int { song.tempoMap.tick(atSeconds: max(0, time)) }

    // MARK: Pointer

    func handle(_ event: ScorePointerEvent) {
        switch event {
        case let .down(point, extendsSelection):
            if isInserting, !extendsSelection {
                insert(at: point)
            } else if let id = point.noteID, tagByID.indices.contains(id) {
                let tag = tagByID[id]
                if extendsSelection {
                    if selection.contains(tag) { selection.remove(tag) } else { selection.insert(tag) }
                } else if !selection.contains(tag) {
                    selection = [tag]
                }
                if let note = notes.first(where: { $0.tag == tag }) { playNote(note.note.pitch) }
                dragOrigin = (notes, 0, 0)
            } else {
                if !extendsSelection { selection = [] }
                cursorTick = snap(tick(at: point.time))
            }
        case let .dragged(point, from):
            guard let origin = dragOrigin, !selection.isEmpty else { return }
            // Steps counted on the diatonic scale, across both staves.
            let dSteps = (from.clef.topLineIndex - from.step) - (point.clef.topLineIndex - point.step)
            let grid = max(1, noteValue.ticks(ticksPerQuarter: ticksPerQuarter))
            let dTicks = Int((Double(tick(at: point.time) - tick(at: from.time)) / Double(grid)).rounded()) * grid
            guard dSteps != origin.dSteps || dTicks != origin.dTicks else { return }
            dragOrigin = (origin.notes, dSteps, dTicks)
            notes = origin.notes.map { tagged in
                guard selection.contains(tagged.tag) else { return tagged }
                var tagged = tagged
                tagged.note.pitch = diatonicTranspose(tagged.note.pitch, by: -dSteps, atTick: tagged.note.startTick)
                tagged.note.startTick = max(0, tagged.note.startTick + dTicks)
                return tagged
            }
            if dSteps != origin.dSteps, let first = notes.first(where: { selection.contains($0.tag) }) { playNote(first.note.pitch) }
            rebuild(save: false)
        case .up:
            if let origin = dragOrigin, origin.dSteps != 0 || origin.dTicks != 0 {
                registerUndo(origin.notes, name: String(localized: "Déplacer"))
                scheduleSave()
            }
            dragOrigin = nil
        case let .doubleClick(point):
            if !isInserting, point.noteID == nil { insert(at: point) }
        }
    }

    // MARK: Editing

    private func insert(at point: ScorePoint) {
        let start = snap(tick(at: point.time))
        let key = song.keySignature(atTick: start)
        let pitch = UInt8(clamping: StaffGeometry.pitch(atStep: point.step, clef: point.clef, key: key).midiPitch)
        let hand: Hand = point.clef == .treble ? .right : .left
        insert(pitch: pitch, at: start, hand: hand)
        cursorTick = start + valueTicks
    }

    private func insert(pitch: UInt8, at start: Int, hand: Hand) {
        if let existing = notes.first(where: { $0.note.startTick == start && $0.note.pitch == pitch }) {
            selection = [existing.tag]
            return
        }
        let note = EditedNote(pitch: pitch, track: track(for: hand), startTick: start, durationTicks: valueTicks)
        change(String(localized: "Ajouter une note")) {
            notes.append(TaggedNote(tag: nextTag, note: note))
            selection = [nextTag]
            nextTag += 1
        }
        lastPitch = pitch
        playNote(pitch)
    }

    /// Inserts a note named by its letter (A–G) at the cursor, in the octave nearest the last note.
    func insertLetter(_ letter: Step) {
        guard isInserting else { return }
        let start = cursorTick ?? 0
        let key = song.keySignature(atTick: start)
        let pitchClass = letter.naturalPitchClass + (key?.alteration(for: letter) ?? 0)
        let candidates = (1...8).map { $0 * 12 + pitchClass }
        let pitch = candidates.min { abs($0 - Int(lastPitch)) < abs($1 - Int(lastPitch)) } ?? 60
        insert(pitch: UInt8(clamping: pitch), at: start, hand: pitch >= Int(PianoKeys.middleC) ? .right : .left)
        cursorTick = start + valueTicks
    }

    /// A key played on the MIDI keyboard: in insert mode, inserted at the cursor. Keys played together
    /// form a chord; the cursor moves on when the next key comes later.
    func midiNote(_ pitch: UInt8) {
        guard isInserting else { return }
        let now = Date()
        let start: Int
        if let chord, now.timeIntervalSince(chord.time) < 0.08 {
            start = chord.tick
        } else {
            start = cursorTick ?? 0
            chord = (start, now)
        }
        insert(pitch: pitch, at: start, hand: pitch >= PianoKeys.middleC ? .right : .left)
        cursorTick = start + valueTicks
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let start = selectionStart
        change(String(localized: "Supprimer")) {
            notes.removeAll { selection.contains($0.tag) }
            selection = []
        }
        if let start { cursorTick = start }
    }

    func transposeSelection(semitones: Int) {
        modifySelection(String(localized: "Transposer")) { note in
            note.pitch = UInt8(clamping: Int(note.pitch) + semitones)
        }
        if let first = selectedNotes.first { playNote(first.pitch) }
    }

    func transposeSelection(steps: Int) {
        modifySelection(String(localized: "Transposer")) { note in
            note.pitch = diatonicTranspose(note.pitch, by: steps, atTick: note.startTick)
        }
        if let first = selectedNotes.first { playNote(first.pitch) }
    }

    /// Moves the selection by one note value, or the cursor when nothing is selected.
    func moveSelection(by slots: Int) {
        let grid = valueTicks
        if selection.isEmpty {
            cursorTick = max(0, (cursorTick ?? 0) + slots * grid)
            return
        }
        modifySelection(String(localized: "Déplacer")) { note in
            note.startTick = max(0, note.startTick + slots * grid)
        }
    }

    func applyNoteValue() {
        let ticks = valueTicks
        modifySelection(String(localized: "Changer la durée")) { $0.durationTicks = ticks }
    }

    enum AccidentalAction { case flat, natural, sharp }

    func applyAccidental(_ action: AccidentalAction) {
        modifySelection(String(localized: "Altération")) { note in
            switch action {
            case .sharp: note.pitch = UInt8(clamping: Int(note.pitch) + 1)
            case .flat: note.pitch = UInt8(clamping: Int(note.pitch) - 1)
            case .natural:
                let spelled = Speller.spell(Int(note.pitch), in: song.keySignature(atTick: note.startTick))
                note.pitch = UInt8(clamping: SpelledPitch(step: spelled.step, alter: 0, octave: spelled.octave).midiPitch)
            }
        }
        if let first = selectedNotes.first { playNote(first.pitch) }
    }

    func setFinger(_ finger: UInt8?) {
        modifySelection(String(localized: "Doigté")) { $0.finger = finger }
    }

    func setHand(_ hand: Hand) {
        guard canChangeHand else { return }
        let track = track(for: hand)
        modifySelection(String(localized: "Changer de main")) { $0.track = track }
    }

    func selectAll() {
        selection = Set(notes.map(\.tag))
    }

    func clearSelection() {
        selection = []
    }

    /// Back to the notes of the song's file. Undoable.
    func restoreOriginal() {
        change(String(localized: "Rétablir l'original")) {
            notes = original.editedNotes.map { note in
                defer { nextTag += 1 }
                return TaggedNote(tag: nextTag, note: note)
            }
            selection = []
        }
    }

    private func diatonicTranspose(_ pitch: UInt8, by steps: Int, atTick tick: Int) -> UInt8 {
        let key = song.keySignature(atTick: tick)
        let spelled = Speller.spell(Int(pitch), in: key)
        let index = spelled.diatonicIndex + steps
        let octave = Int((Double(index) / 7).rounded(.down))
        let step = Step(rawValue: index - octave * 7) ?? .c
        return UInt8(clamping: SpelledPitch(step: step, alter: key?.alteration(for: step) ?? 0, octave: octave).midiPitch)
    }

    private func modifySelection(_ name: String, _ modify: (inout EditedNote) -> Void) {
        guard !selection.isEmpty else { return }
        change(name) {
            for index in notes.indices where selection.contains(notes[index].tag) {
                modify(&notes[index].note)
            }
        }
    }

    private func change(_ name: String, _ body: () -> Void) {
        let before = notes
        body()
        guard notes != before else { return }
        registerUndo(before, name: name)
        rebuild(save: true)
    }

    private func registerUndo(_ snapshot: [TaggedNote], name: String) {
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = model.notes
                model.notes = snapshot
                model.selection.formIntersection(snapshot.map(\.tag))
                model.registerUndo(current, name: name)
                model.rebuild(save: true)
            }
        }
        undoManager?.setActionName(name)
    }

    // MARK: Song and saving

    private func rebuild(save: Bool) {
        notes.sort { EditedNote.isOrderedBefore($0.note, $1.note) }
        song = original.replacingNotes(notes.map(\.note))
        // Match the song's note ids back to tags (equal notes are interchangeable).
        var tagsByNote: [EditedNote: [Int]] = [:]
        for tagged in notes { tagsByNote[tagged.note, default: []].append(tagged.tag) }
        tagByID = song.notes.map { note in
            let edited = EditedNote(note)
            return tagsByNote[edited]?.popLast() ?? -1
        }
        idByTag = Dictionary(tagByID.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        scene = makeScene()
        version += 1
        if save { scheduleSave() }
    }

    private func makeScene() -> SheetScene {
        let hands = song.notes.map { settings.handAssignment.hand(for: $0) }
        let style = PlayerViewModel.sheetStyle(for: song, hands: hands, transpose: 0, rhythmic: true).style
        let keys = song.keySignatures.map { KeySignatureChange(tick: $0.tick, key: $0.key) }
        var scene = SheetScene(style: style, song: song, noteHands: hands, activeHands: [.left, .right], keys: keys,
                               coloredNotes: display.coloredNotes, noteNames: display.showsNoteNames ? display.naming : nil,
                               pointsPerSecond: display.pointsPerSecond * 0.75)
        scene.fingers = PlayerViewModel.fingers(for: song, hands: hands, transpose: 0, display: .written)
        return scene
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the edits now (also when the window closes). Notes equal to the file's remove the edits.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let edited = notes.map(\.note).sorted(by: EditedNote.isOrderedBefore)
        let unchanged = edited == original.editedNotes.sorted(by: EditedNote.isOrderedBefore)
        do {
            if unchanged {
                if library.hasEdits(songID) { library.removeEdits(for: songID) }
            } else {
                try library.saveEdits(edited, for: songID)
            }
            isEdited = !unchanged
            saveError = nil
        } catch {
            saveError = String(localized: "Les modifications n'ont pas pu être enregistrées : \(error.localizedDescription)")
        }
    }
}
