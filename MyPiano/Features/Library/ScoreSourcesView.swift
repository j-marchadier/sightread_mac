import SwiftUI

/// Free score collections. They open in the browser; downloaded files are then imported.
struct ScoreSource: Identifiable {
    let id: String
    let name: String
    let url: URL
    let summary: LocalizedStringKey
    let license: LocalizedStringKey

    static let all: [ScoreSource] = [
        ScoreSource(
            id: "mutopia", name: "Mutopia Project",
            url: URL(string: "https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano")!,
            summary: "Environ 2 000 œuvres classiques gravées avec soin, avec un fichier MIDI pour chacune. Idéal pour une partition rythmique propre.",
            license: "Domaine public et Creative Commons"
        ),
        ScoreSource(
            id: "piano-midi", name: "Classical Piano Midi Page",
            url: URL(string: "http://www.piano-midi.de/")!,
            summary: "Le répertoire classique pour piano, de Bach à Debussy, en fichiers MIDI joués avec expression : la partition simplifiée convient mieux.",
            license: "Creative Commons BY-SA (citer l'auteur, Bernd Krueger)"
        ),
        ScoreSource(
            id: "openscore", name: "OpenScore",
            url: URL(string: "https://musescore.com/openscore")!,
            summary: "Partitions libres transcrites par des bénévoles sur MuseScore. Choisissez « Télécharger › MusicXML » (compte gratuit nécessaire).",
            license: "CC0 (aucune restriction)"
        ),
    ]
}

struct ScoreSourcesView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trouver des partitions").font(.title2.bold())
            Text("Ces collections proposent des partitions libres de droits. Elles s'ouvrent dans votre navigateur ; MyPiano n'accède jamais à Internet.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ScoreSource.all) { source in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(source.name).font(.headline)
                            Spacer()
                            Button("Ouvrir") { openURL(source.url) }
                        }
                        Text(source.summary).fixedSize(horizontal: false, vertical: true)
                        Label(source.license, systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
            }
            Label("Une fois téléchargés, glissez les fichiers sur la fenêtre ou l'icône de MyPiano, utilisez Fichier › Importer… (⌘O), ou rangez-les dans votre dossier surveillé.", systemImage: "square.and.arrow.down")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 520)
    }
}
