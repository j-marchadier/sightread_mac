import AppKit
import MyPianoCore
import MyPianoRendering
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A song to print, with the settings it is practised with (hands, transposition, fingers, note names).
struct PrintableScore {
    let song: Song
    let title: String
    let composer: String?
    let settings: PracticeSettings
    let display: DisplayOptions

    /// The score in rhythmic notation on A4 pages.
    @MainActor
    func pdf() -> Data {
        let hands = song.notes.map { settings.handAssignment.hand(for: $0) }
        let style = PlayerViewModel.sheetStyle(for: song, hands: hands, transpose: settings.transpose, rhythmic: true).style
        let keys = song.keySignatures.map { KeySignatureChange(tick: $0.tick, key: $0.key.transposed(by: settings.transpose)) }
        // Printed staves are about half the size of the on-screen ones: narrower measures keep lines full.
        var scene = SheetScene(
            style: style, song: song, noteHands: hands, activeHands: [.left, .right], keys: keys,
            coloredNotes: display.coloredNotes, noteNames: display.showsNoteNames ? display.naming : nil,
            pointsPerSecond: display.pointsPerSecond * 0.75 * 0.6
        )
        scene.fingers = PlayerViewModel.fingers(for: song, hands: hands, transpose: settings.transpose, display: display.fingering)
        return SheetPDF.render(scene: scene, title: title, subtitle: composer) { page, count in
            String(localized: "\(title) · page \(page) sur \(count)")
        }
    }
}

extension LibraryModel {
    /// A library song with its saved settings and the global display options.
    func printableScore(for id: String) throws -> PrintableScore {
        guard let entry = database.song(id) else { throw CocoaError(.fileNoSuchFile) }
        let song = try song(for: id)
        let settings = entry.settings ?? Preferences.newSongSettings(handAssignment: HandAssigner.assign(song))
        return PrintableScore(song: song, title: entry.title, composer: entry.composer, settings: settings, display: Preferences.display)
    }
}

enum ScoreExportRequest: Equatable {
    case pdf
    case print
}

/// Lets the File menu export or print the score of the frontmost song.
struct ScoreExportAction {
    let perform: (ScoreExportRequest) -> Void
}

private struct ScoreExportKey: FocusedValueKey { typealias Value = ScoreExportAction }

extension FocusedValues {
    var scoreExport: ScoreExportAction? {
        get { self[ScoreExportKey.self] }
        set { self[ScoreExportKey.self] = newValue }
    }
}

extension View {
    /// Handles export and print requests for the score of `source`, from `request` or the File menu.
    func scoreExport(request: Binding<ScoreExportRequest?>, source: @escaping @MainActor () throws -> PrintableScore) -> some View {
        modifier(ScoreExporter(request: request, source: source))
    }
}

private struct ScoreExporter: ViewModifier {
    @Binding var request: ScoreExportRequest?
    let source: @MainActor () throws -> PrintableScore
    @State private var document: PDFFile?
    @State private var filename = ""
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.scoreExport, ScoreExportAction { request = $0 })
            .onChange(of: request) { _, newValue in
                guard let newValue else { return }
                request = nil
                perform(newValue)
            }
            .fileExporter(isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } }),
                          document: document, contentType: .pdf, defaultFilename: filename) { result in
                if case let .failure(error) = result { errorMessage = error.localizedDescription }
            }
            .alert("Impossible de créer la partition", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func perform(_ request: ScoreExportRequest) {
        do {
            let source = try source()
            let data = source.pdf()
            switch request {
            case .pdf:
                filename = source.title
                document = PDFFile(data: data)
            case .print:
                Self.print(data, title: source.title)
            }
        } catch let error as SongLoadingError {
            errorMessage = LibraryModel.describe(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the system print panel, which also offers "Save as PDF".
    private static func print(_ data: Data, title: String) {
        guard let pdf = PDFDocument(data: data),
              let operation = pdf.printOperation(for: NSPrintInfo(), scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { return }
        operation.jobTitle = title
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}

/// A rendered score, written by the save panel.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Toolbar menu exporting or printing the score.
struct ScoreExportMenu: View {
    @Binding var request: ScoreExportRequest?

    var body: some View {
        Menu {
            Button("Exporter en PDF…") { request = .pdf }
            Button("Imprimer…") { request = .print }
        } label: {
            Label("Partition", systemImage: "square.and.arrow.up")
        }
        .help("Exporter ou imprimer la partition")
    }
}
