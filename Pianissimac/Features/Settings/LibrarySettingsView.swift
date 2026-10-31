import SwiftUI
import UniformTypeIdentifiers

/// Settings › Bibliothèque: the watched folder.
struct LibrarySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isChoosing = false

    var body: some View {
        let folder = model.watchedFolder
        Form {
            Section {
                LabeledContent("Dossier surveillé") {
                    switch folder.status {
                    case .off:
                        Text("Aucun").foregroundStyle(.secondary)
                    case .watching:
                        Label(folder.url?.lastPathComponent ?? "", systemImage: "folder")
                            .help(folder.url?.path ?? "")
                    case .accessLost:
                        Label("Accès perdu : choisissez à nouveau le dossier", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                HStack {
                    Button(folder.status == .off ? "Choisir un dossier…" : "Changer de dossier…") { isChoosing = true }
                    if folder.status != .off {
                        Button("Ne plus surveiller") { folder.stop() }
                    }
                }
            } footer: {
                Text("Les fichiers MIDI et MusicXML ajoutés à ce dossier (et à ses sous-dossiers) apparaissent dans la bibliothèque en quelques secondes. Un fichier supprimé du dossier disparaît de la bibliothèque.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { folder.choose(url) }
        }
    }
}
