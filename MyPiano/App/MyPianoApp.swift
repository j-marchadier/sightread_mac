import SwiftUI

@main
struct MyPianoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 1100, height: 720)

        Window("Clavier et son", id: WindowID.keyboardDiagnostics) {
            KeyboardDiagnosticsView()
                .environment(model)
                .task { model.start() }
        }
        .defaultSize(width: 520, height: 680)

        Window("Lecteur de test", id: WindowID.practiceTest) {
            PracticeTestView()
                .environment(model)
        }
        .defaultSize(width: 540, height: 760)
    }
}

enum WindowID {
    static let keyboardDiagnostics = "keyboard-diagnostics"
    static let practiceTest = "practice-test"
}
