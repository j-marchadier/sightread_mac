import SwiftUI

/// Welcome window shown on first launch (and from the Help menu).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.onboardingDone) private var onboardingDone = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "pianokeys")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Bienvenue dans MyPiano").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                feature("cable.connector", "Branchez votre clavier MIDI",
                        "Il est détecté automatiquement. Vérifiez-le dans Réglages › Clavier MIDI.")
                feature("music.note.list", "Choisissez un morceau",
                        "Une bibliothèque de pièces libres de droits est incluse ; importez vos fichiers MIDI ou MusicXML avec ⌘O.")
                feature("graduationcap", "Apprenez à votre rythme",
                        "Le mode Attendre patiente sur chaque note, une main à la fois, à la vitesse de votre choix.")
                feature("eye", "Lisez la musique",
                        "Passez des notes qui tombent à la partition, et entraînez-vous avec les exercices de lecture.")
            }
            .frame(maxWidth: 440)
            HStack {
                keyboardStatus
                Spacer()
                Button("Commencer") {
                    onboardingDone = true
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 440)
        }
        .padding(36)
        .task { model.start() }
    }

    @ViewBuilder
    private var keyboardStatus: some View {
        switch model.midi.status {
        case .noKeyboard:
            Label("Aucun clavier détecté", systemImage: "pianokeys").foregroundStyle(.secondary)
        case let .connected(names):
            Label(names.first ?? "", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
