import SwiftUI

@main
struct MyPianoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("MyPiano", id: WindowID.main) {
            MainWindow()
                .environment(model)
                .task {
                    model.start()
                    appDelegate.openHandler = { [model] urls in model.openFiles(urls) }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { MyPianoCommands(model: model) }

        WindowGroup("Lecture", id: WindowID.player, for: PlayerTarget.self) { $target in
            if let target {
                PlayerWindow(target: target)
                    .environment(model)
            }
        }
        .defaultSize(width: 1240, height: 800)
        .handlesExternalEvents(matching: [])

        Window("Jeu libre", id: WindowID.freePlay) {
            FreePlayView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 1100, height: 600)

        Window("Bienvenue", id: WindowID.welcome) {
            OnboardingView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Trouver des partitions", id: WindowID.scoreSources) {
            ScoreSourcesView()
        }
        .windowResizability(.contentSize)

        WindowGroup("Modifier la partition", id: WindowID.scoreEditor, for: String.self) { $songID in
            if let songID {
                ScoreEditorWindow(songID: songID)
                    .environment(model)
                    .task { model.start() }
            }
        }
        .defaultSize(width: 1180, height: 780)
        .handlesExternalEvents(matching: [])

        Window("À propos de MyPiano", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Mentions", id: WindowID.acknowledgements) {
            AcknowledgementsView()
        }
        .defaultSize(width: 720, height: 640)

        Settings {
            SettingsView()
                .environment(model)
                .task { model.start() }
        }
    }
}

enum WindowID {
    static let main = "main"
    static let player = "player"
    static let freePlay = "free-play"
    static let welcome = "welcome"
    static let scoreSources = "score-sources"
    static let about = "about"
    static let scoreEditor = "score-editor"
    static let acknowledgements = "acknowledgements"
}
