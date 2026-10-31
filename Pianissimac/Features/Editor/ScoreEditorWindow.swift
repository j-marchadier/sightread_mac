import PianissimacCore
import PianissimacRendering
import SwiftUI

/// Root of a score editor window: opens the song, then shows the editor.
struct ScoreEditorWindow: View {
    @Environment(AppModel.self) private var model
    let songID: String
    @State private var editor: ScoreEditorModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let editor {
                ScoreEditorView(editor: editor)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Impossible d'ouvrir le morceau", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task {
            guard editor == nil else { return }
            do {
                editor = try ScoreEditorModel(songID: songID, library: model.library) { [model] pitch in model.previewNote(pitch) }
            } catch let error as SongLoadingError {
                loadError = LibraryModel.describe(error)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

/// The score with its editing palette.
private struct ScoreEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Bindable var editor: ScoreEditorModel
    @State private var confirmsRestore = false
    @FocusState private var isFocused: Bool

    var body: some View {
        PianissimacRendering.ScoreEditorView(scene: editor.scene, version: editor.version, selection: editor.selectedNoteIDs,
                                         cursor: editor.isInserting ? editor.cursorTime : nil) { event in
            editor.handle(event)
            isFocused = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onCommand(#selector(NSResponder.selectAll(_:))) { editor.selectAll() }
        .onCommand(#selector(NSText.delete(_:))) { editor.deleteSelection() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorPalette(editor: editor)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .navigationTitle(Text("Modifier « \(editor.title) »"))
        .navigationSubtitle(status)
        .toolbar {
            ToolbarItem {
                Button { openWindow(id: WindowID.player, value: PlayerTarget.song(id: editor.songID)) } label: {
                    Label("Jouer", systemImage: "play.fill")
                }
                .help("Ouvrir le morceau dans le lecteur")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { confirmsRestore = true } label: {
                    Label("Rétablir l'original", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(!editor.isEdited)
                .help("Revenir aux notes d'origine du morceau")
            }
        }
        .confirmationDialog("Rétablir les notes d'origine ?", isPresented: $confirmsRestore) {
            Button("Rétablir l'original", role: .destructive) { editor.restoreOriginal() }
        } message: {
            Text("Toutes vos modifications de ce morceau seront retirées. Vous pourrez encore annuler avec ⌘Z tant que cette fenêtre est ouverte.")
        }
        .alert("Enregistrement impossible", isPresented: Binding(get: { editor.saveError != nil }, set: { if !$0 { editor.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.saveError ?? "")
        }
        .onAppear {
            editor.undoManager = undoManager
            isFocused = true
            let target = editor
            model.noteObserver = { [weak target] pitch in target?.midiNote(pitch) }
        }
        .onChange(of: undoManager) { _, manager in editor.undoManager = manager }
        .onDisappear {
            editor.saveNow()
            model.noteObserver = nil
        }
    }

    private var status: String {
        let selected = editor.selectedNotes
        if selected.count == 1, let note = selected.first {
            let name = Preferences.noteNaming.name(of: Speller.spell(Int(note.pitch), in: editor.song.keySignature(atTick: note.startTick)),
                                                    includeOctave: true)
            let measure = editor.song.measures.isEmpty ? 1 : editor.song.measures[editor.song.measureIndex(atTick: note.startTick)].number
            var parts = [name, String(localized: "mesure \(measure)")]
            if let hand = editor.hand(of: note) { parts.append(hand == .right ? String(localized: "main droite") : String(localized: "main gauche")) }
            if let finger = note.finger { parts.append(String(localized: "doigt \(finger)")) }
            return parts.joined(separator: " · ")
        }
        if selected.count > 1 { return String(localized: "\(selected.count) notes sélectionnées") }
        if editor.isInserting { return String(localized: "Saisie : cliquez sur la portée, tapez A à G ou jouez au clavier MIDI") }
        return editor.isEdited ? String(localized: "Modifié · enregistré automatiquement") : String(localized: "Notes d'origine")
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        let option = press.modifiers.contains(.option)
        switch press.key {
        case .delete, .deleteForward:
            editor.deleteSelection()
        case .upArrow:
            if option { editor.transposeSelection(steps: 1) } else { editor.transposeSelection(semitones: command ? 12 : 1) }
        case .downArrow:
            if option { editor.transposeSelection(steps: -1) } else { editor.transposeSelection(semitones: command ? -12 : -1) }
        case .leftArrow:
            editor.moveSelection(by: -1)
        case .rightArrow:
            editor.moveSelection(by: 1)
        case .escape:
            if editor.isInserting { editor.isInserting = false } else { editor.clearSelection() }
        default:
            guard !command, let character = press.characters.lowercased().first else { return .ignored }
            switch character {
            case "n": editor.isInserting.toggle()
            case ".": editor.isDotted.toggle(); editor.applyNoteValue()
            case "1", "2", "3", "4", "5": editor.setFinger(UInt8(String(character)))
            case "0": editor.setFinger(nil)
            case "l": editor.setHand(.left)
            case "r": editor.setHand(.right)
            default:
                guard editor.isInserting, let step = Step(letter: String(character).uppercased()) else { return .ignored }
                editor.insertLetter(step)
            }
        }
        return .handled
    }
}

/// Insert mode, note values, accidentals, hands and fingers, floating in Liquid Glass under the score.
private struct EditorPalette: View {
    @Bindable var editor: ScoreEditorModel

    private static let values: [(NoteValue, String, LocalizedStringKey)] = [
        (.whole, "\u{ECA2}", "Ronde"), (.half, "\u{ECA3}", "Blanche"), (.quarter, "\u{ECA5}", "Noire"),
        (.eighth, "\u{ECA7}", "Croche"), (.sixteenth, "\u{ECA9}", "Double croche"), (.thirtySecond, "\u{ECAB}", "Triple croche"),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Toggle(isOn: $editor.isInserting) {
                    Label("Saisie", systemImage: "pencil")
                }
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .tint(editor.isInserting ? .accentColor : .clear)
                .help("Saisir des notes : clic sur la portée, lettres A à G ou clavier MIDI (N)")

                group {
                    ForEach(Self.values, id: \.0) { value, glyph, name in
                        musicButton(glyph, name, isOn: editor.noteValue == value) {
                            editor.noteValue = value
                            editor.applyNoteValue()
                        }
                    }
                    musicButton("\u{ECB7}", "Pointée (.)", isOn: editor.isDotted) {
                        editor.isDotted.toggle()
                        editor.applyNoteValue()
                    }
                }

                group {
                    textButton("♭", "Baisser d'un demi-ton") { editor.applyAccidental(.flat) }
                    textButton("♮", "Bécarre") { editor.applyAccidental(.natural) }
                    textButton("♯", "Monter d'un demi-ton") { editor.applyAccidental(.sharp) }
                }

                if editor.canChangeHand {
                    group {
                        textButton("MG", "Main gauche (L)") { editor.setHand(.left) }
                        textButton("MD", "Main droite (R)") { editor.setHand(.right) }
                    }
                }

                group {
                    ForEach(1...5, id: \.self) { finger in
                        textButton("\(finger)", "Doigt \(finger)") { editor.setFinger(UInt8(finger)) }
                    }
                    Button { editor.setFinger(nil) } label: {
                        Image(systemName: "xmark").frame(width: 22, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("Sans doigté (0)")
                }

                Button(role: .destructive) { editor.deleteSelection() } label: {
                    Label("Supprimer", systemImage: "trash").labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(.clear)
                .disabled(editor.selection.isEmpty)
                .help("Supprimer les notes sélectionnées (⌫)")
            }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .glassEffect()
    }

    private func musicButton(_ glyph: String, _ name: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.custom("Leland", size: 24))
                .frame(width: 26, height: 28)
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .background(isOn ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(name)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func textButton(_ text: String, _ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .frame(minWidth: 22, minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(editor.selection.isEmpty)
        .help(help)
    }
}
