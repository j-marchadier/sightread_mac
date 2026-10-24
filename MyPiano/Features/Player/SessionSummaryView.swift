import MyPianoCore
import SwiftUI

/// Shown when the end of the song is reached.
struct SessionSummaryView: View {
    enum Action { case again, newExercise, close }

    let summary: SessionSummary
    let isExercise: Bool
    let onAction: (Action) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(headline).font(.title2.bold())
            if summary.mode != .listen {
                StatsGrid(stats: summary.stats, isJudged: true)
            }
            Text("Temps de pratique : \(Duration.seconds(summary.practiceSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))")
                .foregroundStyle(.secondary)
            HStack {
                Button("Fermer") { onAction(.close) }
                    .keyboardShortcut(.cancelAction)
                if isExercise {
                    Button("Nouvelle série") { onAction(.newExercise) }
                        .keyboardShortcut(.defaultAction)
                    Button("Recommencer") { onAction(.again) }
                } else {
                    Button("Recommencer") { onAction(.again) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 360)
    }

    private var accuracy: Double { summary.stats.accuracy }

    private var symbol: String {
        if summary.mode == .listen { return "headphones" }
        return accuracy >= 0.9 ? "star.fill" : accuracy >= 0.6 ? "hand.thumbsup.fill" : "music.note"
    }

    private var headline: String {
        if summary.mode == .listen { return String(localized: "Écoute terminée") }
        if accuracy >= 0.9 { return String(localized: "Excellent !") }
        if accuracy >= 0.6 { return String(localized: "Bien joué !") }
        return String(localized: "Continuez, ça vient !")
    }
}
