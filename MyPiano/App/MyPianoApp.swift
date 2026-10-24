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
}
